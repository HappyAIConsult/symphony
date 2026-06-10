defmodule SymphonyElixir.Claude.AppServerTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Claude.AppServer
  alias SymphonyElixir.Linear.Issue

  setup do
    root = Path.join(System.tmp_dir!(), "symphony-claude-#{System.unique_integer([:positive])}")
    ws = Path.join(root, "ENG-7")
    File.mkdir_p!(ws)

    bin_dir = Path.join(root, "bin")
    File.mkdir_p!(bin_dir)
    fake = Path.join(bin_dir, "claude")
    argv_trace = Path.join(root, "argv.log")

    script = """
    #!/bin/sh
    printf '%s\\n' "$*" >> "#{argv_trace}"
    printf '%s\\n' '{"type":"system","subtype":"init","session_id":"s-1","tools":[]}'
    printf '%s\\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}],"usage":{"output_tokens":2}}}'
    printf '%s\\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","usage":{"input_tokens":1,"output_tokens":2},"total_cost_usd":0.001,"num_turns":1}'
    exit 0
    """

    File.write!(fake, script)
    File.chmod!(fake, 0o755)

    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "claude",
      workspace_root: root,
      claude_bin: fake
    )

    on_exit(fn -> File.rm_rf(root) end)

    {:ok, ws: ws, argv_trace: argv_trace, root: root, fake: fake}
  end

  defp issue do
    %Issue{id: "id-7", identifier: "ENG-7", title: "Test", state: "In Progress", url: "http://x", labels: []}
  end

  test "start_session validates cwd and returns a claude session map", %{ws: ws} do
    assert {:ok, session} = AppServer.start_session(ws, [])
    assert session.kind == :claude
    assert is_binary(session.thread_id)
    assert String.ends_with?(session.workspace, "ENG-7")
    assert :ok = AppServer.stop_session(session)
  end

  test "run_turn streams events and returns the result tuple", %{ws: ws} do
    test_pid = self()
    {:ok, session} = AppServer.start_session(ws, [])

    assert {:ok, result} =
             AppServer.run_turn(session, "do the task", issue(), on_message: fn msg -> send(test_pid, {:claude_msg, msg}) end)

    assert result.result == "done"
    assert is_binary(result.session_id)

    assert_receive {:claude_msg, %{event: :session_started}}
    assert_receive {:claude_msg, %{event: :turn_completed}}
    AppServer.stop_session(session)
  end

  test "first turn omits --resume, second turn includes it", %{ws: ws, argv_trace: trace} do
    {:ok, session} = AppServer.start_session(ws, [])
    {:ok, _} = AppServer.run_turn(session, "turn 1", issue(), on_message: fn _ -> :ok end)
    {:ok, _} = AppServer.run_turn(session, "turn 2", issue(), on_message: fn _ -> :ok end)
    AppServer.stop_session(session)

    [first, second | _] = trace |> File.read!() |> String.split("\n", trim: true)
    refute first =~ "--resume"
    assert first =~ "--session-id"
    assert second =~ "--resume"
  end

  test "passes --mcp-config when server endpoint is configured", %{ws: ws, argv_trace: trace, root: root, fake: fake} do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "claude",
      workspace_root: root,
      claude_bin: fake,
      server_port: 4599,
      server_host: "127.0.0.1"
    )

    {:ok, session} = AppServer.start_session(ws, [])
    {:ok, _} = AppServer.run_turn(session, "go", issue(), on_message: fn _ -> :ok end)
    AppServer.stop_session(session)

    argv = File.read!(trace)
    assert argv =~ "--mcp-config"
    assert argv =~ "127.0.0.1:4599/mcp"
  end

  test "emits Claude session lifecycle logs for diagnostics", %{ws: ws} do
    log =
      capture_log([level: :info], fn ->
        {:ok, session} = AppServer.start_session(ws, [])
        {:ok, _} = AppServer.run_turn(session, "go", issue(), on_message: fn _ -> :ok end)
        AppServer.stop_session(session)
      end)

    assert log =~ "Claude session started for issue_id=id-7 issue_identifier=ENG-7 session_id="
    assert log =~ "Claude session completed for issue_id=id-7 issue_identifier=ENG-7 session_id="
  end
end
