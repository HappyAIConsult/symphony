defmodule SymphonyElixir.Claude.AppServer do
  @moduledoc """
  Claude Code бэкенд для Symphony. Запускает `claude -p --output-format stream-json`
  в рабочей директории задачи на каждый turn и маппит события в словарь Symphony.
  Реализует тот же интерфейс, что Codex.AppServer.
  """

  @behaviour SymphonyElixir.AgentBackend

  require Logger

  alias SymphonyElixir.{AgentWorkspaceGuard, Claude.StreamMapper, Config, SSH, UUID}

  @port_line_bytes 1_048_576
  @session_marker ".symphony-claude-session"

  @impl true
  @spec start_session(Path.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Keyword.get(opts, :worker_host)

    with {:ok, expanded_workspace} <-
           AgentWorkspaceGuard.validate(workspace, Config.settings!().workspace.root, worker_host) do
      {:ok,
       %{
         kind: :claude,
         thread_id: UUID.v4(),
         workspace: expanded_workspace,
         worker_host: worker_host,
         metadata: base_metadata(worker_host)
       }}
    end
  end

  @impl true
  @spec run_turn(map(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(session, prompt, issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, fn _ -> :ok end)
    {:ok, rt} = Config.claude_runtime_settings()

    turn_number = turn_number(session)
    session_id = "#{session.thread_id}-#{turn_number}"
    emit(on_message, :session_started, %{session_id: session_id, thread_id: session.thread_id}, session.metadata)
    Logger.info("Claude session started for #{issue_context(issue)} session_id=#{session_id}")

    command = build_command(session, prompt, rt)

    case start_port(session.workspace, session.worker_host, command) do
      {:ok, port} ->
        result =
          try do
            port
            |> receive_loop(on_message, rt.turn_timeout_ms, "", session, %{ok: false, result: nil, usage: nil})
            |> finalize(session, session_id, turn_number, on_message)
          after
            mark_session_started(session)
            close_port(port)
          end

        log_outcome(result, issue, session_id)
        result

      {:error, reason} ->
        emit(on_message, :startup_failed, %{reason: reason}, session.metadata)
        Logger.error("Claude session failed for #{issue_context(issue)}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp log_outcome({:ok, _result}, issue, session_id) do
    Logger.info("Claude session completed for #{issue_context(issue)} session_id=#{session_id}")
  end

  defp log_outcome({:error, reason}, issue, session_id) do
    Logger.warning("Claude session ended with error for #{issue_context(issue)} session_id=#{session_id}: #{inspect(reason)}")
  end

  defp issue_context(%{id: id, identifier: identifier}), do: "issue_id=#{id} issue_identifier=#{identifier}"
  defp issue_context(_issue), do: "issue_id=unknown issue_identifier=unknown"

  @impl true
  @spec stop_session(map()) :: :ok
  def stop_session(_session), do: :ok

  # --- сборка команды ---

  defp build_command(session, prompt, rt) do
    resume_args =
      if resumable?(session) do
        ["--resume", session.thread_id]
      else
        ["--session-id", session.thread_id]
      end

    base =
      [
        shell_escape(rt.bin),
        "-p",
        shell_escape(prompt),
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        rt.permission_mode
      ] ++
        resume_args ++
        model_args(rt) ++
        tool_args(rt) ++
        mcp_args(rt) ++
        plugin_args(rt) ++
        add_dir_args(rt) ++
        budget_args(rt) ++
        Enum.map(rt.extra_args, &shell_escape/1)

    Enum.join(base, " ")
  end

  defp model_args(%{model: model}) when is_binary(model), do: ["--model", model]
  defp model_args(_), do: []

  defp tool_args(rt) do
    allow =
      case rt.allowed_tools do
        [] -> []
        tools -> ["--allowedTools", Enum.join(tools, ",")]
      end

    disallow =
      case rt.disallowed_tools do
        [] -> []
        tools -> ["--disallowedTools", Enum.join(tools, ",")]
      end

    allow ++ disallow
  end

  defp budget_args(%{max_budget_usd: usd}) when is_float(usd), do: ["--max-budget-usd", to_string(usd)]
  defp budget_args(_), do: []

  defp plugin_args(%{plugin_dir: dir}) when is_binary(dir) and dir != "",
    do: ["--plugin-dir", shell_escape(dir)]

  defp plugin_args(_rt), do: []

  defp add_dir_args(%{add_dirs: dirs}) when is_list(dirs) do
    Enum.flat_map(dirs, fn dir -> ["--add-dir", shell_escape(dir)] end)
  end

  defp add_dir_args(_rt), do: []

  defp mcp_args(rt) do
    case mcp_url() do
      url when is_binary(url) ->
        config = Jason.encode!(%{"mcpServers" => %{"linear" => mcp_server_entry(url, rt)}})
        ["--mcp-config", shell_escape(config), "--strict-mcp-config"]

      nil ->
        []
    end
  end

  defp mcp_url do
    case System.get_env("SYMPHONY_MCP_URL") do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        settings = Config.settings!()

        case Config.server_port() do
          port when is_integer(port) and port > 0 ->
            "http://#{settings.server.host}:#{port}/mcp"

          _ ->
            nil
        end
    end
  end

  defp mcp_server_entry(url, %{mcp_token: token}) when is_binary(token) do
    %{"type" => "http", "url" => url, "headers" => %{"Authorization" => "Bearer #{token}"}}
  end

  defp mcp_server_entry(url, _rt), do: %{"type" => "http", "url" => url}

  # --- порт/процесс (зеркало Codex.AppServer.start_port) ---

  defp start_port(workspace, nil, command) do
    case System.find_executable("bash") do
      nil ->
        {:error, :bash_not_found}

      executable ->
        port =
          Port.open(
            {:spawn_executable, String.to_charlist(executable)},
            [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              args: [~c"-lc", String.to_charlist(command)],
              cd: String.to_charlist(workspace),
              env: [{~c"CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD", ~c"1"}],
              line: @port_line_bytes
            ]
          )

        {:ok, port}
    end
  end

  defp start_port(workspace, worker_host, command) when is_binary(worker_host) do
    remote = "cd #{shell_escape(workspace)} && #{command}"
    SSH.start_port(worker_host, remote, line: @port_line_bytes)
  end

  defp receive_loop(port, on_message, timeout_ms, pending, session, acc) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        line = pending <> to_string(chunk)
        handle_line(port, on_message, line, timeout_ms, session, acc)

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(port, on_message, timeout_ms, pending <> to_string(chunk), session, acc)

      {^port, {:exit_status, 0}} ->
        acc

      {^port, {:exit_status, status}} ->
        if acc.ok, do: acc, else: %{acc | result: {:error, {:port_exit, status}}}
    after
      timeout_ms ->
        %{acc | result: {:error, :turn_timeout}}
    end
  end

  defp handle_line(port, on_message, line, timeout_ms, session, acc) do
    case Jason.decode(line) do
      {:ok, decoded} ->
        case StreamMapper.classify(decoded) do
          {:event, event, details} ->
            emit(on_message, event, details, with_usage(session.metadata, details))
            receive_loop(port, on_message, timeout_ms, "", session, acc)

          {:result, :ok, details} ->
            emit(on_message, :turn_completed, details, with_usage(session.metadata, details))
            receive_loop(port, on_message, timeout_ms, "", session, %{acc | ok: true, result: {:ok, details}, usage: details.usage})

          {:result, :error, details} ->
            emit(on_message, :turn_failed, details, with_usage(session.metadata, details))
            receive_loop(port, on_message, timeout_ms, "", session, %{acc | result: {:error, {:turn_failed, details}}})
        end

      {:error, _} ->
        if String.trim(line) != "" and String.starts_with?(String.trim_leading(line), "{") do
          emit(on_message, :malformed, %{payload: line, raw: line}, session.metadata)
        else
          log_non_json(line)
        end

        receive_loop(port, on_message, timeout_ms, "", session, acc)
    end
  end

  defp finalize(acc, session, session_id, turn_number, on_message) do
    case acc.result do
      {:ok, details} ->
        {:ok,
         %{
           result: details.result,
           session_id: session_id,
           thread_id: session.thread_id,
           turn_id: turn_number
         }}

      {:error, reason} ->
        emit(on_message, :turn_ended_with_error, %{session_id: session_id, reason: reason}, session.metadata)
        {:error, reason}

      nil ->
        reason = {:no_result, session_id}
        emit(on_message, :turn_ended_with_error, %{session_id: session_id, reason: reason}, session.metadata)
        {:error, reason}
    end
  end

  # --- мультитёрн через маркер в воркспейсе ---

  defp resumable?(session), do: File.exists?(Path.join(session.workspace, @session_marker))

  defp turn_number(session) do
    if resumable?(session), do: read_turn(session) + 1, else: 1
  end

  defp mark_session_started(session) do
    path = Path.join(session.workspace, @session_marker)
    next = if File.exists?(path), do: read_turn(session) + 1, else: 1
    File.write(path, "#{session.thread_id}\n#{next}\n")
  end

  defp read_turn(session) do
    case File.read(Path.join(session.workspace, @session_marker)) do
      {:ok, content} ->
        case content |> String.split("\n", trim: true) |> List.last() |> Integer.parse() do
          {n, _} -> n
          _ -> 1
        end

      _ ->
        1
    end
  end

  # --- утилиты ---

  defp emit(on_message, event, details, metadata) when is_function(on_message, 1) do
    message =
      metadata
      |> Map.merge(details)
      |> Map.put(:event, event)
      |> Map.put(:timestamp, DateTime.utc_now())

    on_message.(message)
  end

  defp with_usage(metadata, %{usage: usage}) when is_map(usage), do: Map.put(metadata, :usage, usage)
  defp with_usage(metadata, _details), do: metadata

  defp base_metadata(worker_host) when is_binary(worker_host), do: %{worker_host: worker_host}
  defp base_metadata(_), do: %{}

  defp close_port(port) when is_port(port) do
    case :erlang.port_info(port) do
      :undefined ->
        :ok

      _ ->
        try do
          Port.close(port)
          :ok
        rescue
          ArgumentError -> :ok
        end
    end
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp log_non_json(line) do
    text = line |> String.trim() |> String.slice(0, 1_000)

    if text != "" do
      if String.match?(text, ~r/\b(error|warn|warning|failed|fatal|panic|exception)\b/i) do
        Logger.warning("Claude stream output: #{text}")
      else
        Logger.debug("Claude stream output: #{text}")
      end
    end
  end
end
