defmodule SymphonyElixir.AgentBackendTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend

  test "resolves the codex backend by default" do
    write_workflow_file!(Workflow.workflow_file_path())
    assert AgentBackend.resolve() == SymphonyElixir.Codex.AppServer
  end

  test "resolves the claude backend when agent.kind == claude" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "claude")
    assert AgentBackend.resolve() == SymphonyElixir.Claude.AppServer
  end

  test "for/1 maps atoms to modules" do
    assert AgentBackend.for(:codex) == SymphonyElixir.Codex.AppServer
    assert AgentBackend.for(:claude) == SymphonyElixir.Claude.AppServer
  end
end
