defmodule SymphonyElixir.AgentRunnerBackendTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.AgentBackend

  test "AgentRunner uses the resolver which honours agent.kind" do
    write_workflow_file!(Workflow.workflow_file_path(), agent_kind: "claude")
    assert AgentBackend.resolve() == SymphonyElixir.Claude.AppServer

    write_workflow_file!(Workflow.workflow_file_path())
    assert AgentBackend.resolve() == SymphonyElixir.Codex.AppServer
  end
end
