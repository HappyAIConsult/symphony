defmodule SymphonyElixir.AgentWorkspaceGuardTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.AgentWorkspaceGuard

  setup do
    root = Path.join(System.tmp_dir!(), "symphony-guard-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    {:ok, root: root}
  end

  test "accepts a directory inside the workspace root", %{root: root} do
    ws = Path.join(root, "ENG-1")
    File.mkdir_p!(ws)
    assert {:ok, canonical} = AgentWorkspaceGuard.validate(ws, root, nil)
    assert String.ends_with?(canonical, "ENG-1")
  end

  test "rejects the workspace root itself", %{root: root} do
    assert {:error, {:invalid_workspace_cwd, :workspace_root, _}} =
             AgentWorkspaceGuard.validate(root, root, nil)
  end

  test "rejects a path outside the workspace root", %{root: root} do
    outside = Path.join(System.tmp_dir!(), "symphony-outside-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf(outside) end)

    assert {:error, {:invalid_workspace_cwd, :outside_workspace_root, _, _}} =
             AgentWorkspaceGuard.validate(outside, root, nil)
  end

  test "passes remote workspaces through with basic validation" do
    assert {:ok, "/remote/ws"} = AgentWorkspaceGuard.validate("/remote/ws", "/ignored", "host-1")

    assert {:error, {:invalid_workspace_cwd, :empty_remote_workspace, "host-1"}} =
             AgentWorkspaceGuard.validate("   ", "/ignored", "host-1")
  end
end
