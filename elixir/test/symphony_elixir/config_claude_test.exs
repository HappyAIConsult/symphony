defmodule SymphonyElixir.ConfigClaudeTest do
  use SymphonyElixir.TestSupport

  test "agent.kind defaults to codex and is overridable to claude" do
    write_workflow_file!(Workflow.workflow_file_path())
    assert Config.settings!().agent.kind == "codex"

    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "claude")
    assert Config.settings!().agent.kind == "claude"
  end

  test "claude section parses with sensible defaults" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "claude")
    claude = Config.settings!().claude

    assert claude.bin == "claude"
    assert claude.permission_mode == "bypassPermissions"
    assert claude.auth == "subscription"
    assert claude.turn_timeout_ms == 3_600_000
    assert claude.read_timeout_ms == 5_000
  end

  test "claude section honours overrides" do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "claude",
      claude_bin: "/usr/local/bin/claude",
      claude_model: "opus",
      claude_permission_mode: "acceptEdits",
      claude_auth: "api_key"
    )

    claude = Config.settings!().claude
    assert claude.bin == "/usr/local/bin/claude"
    assert claude.model == "opus"
    assert claude.permission_mode == "acceptEdits"
    assert claude.auth == "api_key"
  end
end
