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

  test "agent_kind/0 returns the configured backend as an atom" do
    write_workflow_file!(Workflow.workflow_file_path())
    assert Config.agent_kind() == :codex

    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "claude")
    assert Config.agent_kind() == :claude
  end

  test "claude_runtime_settings/0 surfaces the claude policy fields" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "claude", claude_model: "sonnet")
    assert {:ok, rt} = Config.claude_runtime_settings()
    assert rt.bin == "claude"
    assert rt.permission_mode == "bypassPermissions"
    assert rt.model == "sonnet"
    assert rt.allowed_tools == ["mcp__linear__linear_graphql"]
    assert rt.turn_timeout_ms == 3_600_000
  end

  test "claude plugin_dir and add_dirs parse and surface via runtime settings" do
    write_workflow_file!(Workflow.workflow_file_path(),
      agent_kind: "claude",
      claude_plugin_dir: "/home/u/sym/knowledge/sym-plugin",
      claude_add_dirs: ["/home/u/sym/knowledge"]
    )

    c = Config.settings!().claude
    assert c.plugin_dir == "/home/u/sym/knowledge/sym-plugin"
    assert c.add_dirs == ["/home/u/sym/knowledge"]

    assert {:ok, rt} = Config.claude_runtime_settings()
    assert rt.plugin_dir == "/home/u/sym/knowledge/sym-plugin"
    assert rt.add_dirs == ["/home/u/sym/knowledge"]
  end
end
