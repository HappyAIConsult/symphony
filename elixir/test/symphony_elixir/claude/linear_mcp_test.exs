defmodule SymphonyElixir.Claude.LinearMcpTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.LinearMcp

  test "initialize returns protocol + server info" do
    resp = LinearMcp.handle_request(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}})
    assert resp["id"] == 1
    assert resp["result"]["serverInfo"]["name"] == "symphony-linear"
    assert is_binary(resp["result"]["protocolVersion"])
  end

  test "tools/list exposes linear_graphql with its input schema" do
    resp = LinearMcp.handle_request(%{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}})
    [tool] = resp["result"]["tools"]
    assert tool["name"] == "linear_graphql"
    assert tool["inputSchema"]["required"] == ["query"]
  end

  test "tools/call linear_graphql delegates to the tool executor" do
    executor = fn "linear_graphql", %{"query" => "query { viewer { id } }"} ->
      %{
        "success" => true,
        "output" => "{\"data\":{}}",
        "contentItems" => [%{"type" => "inputText", "text" => "{\"data\":{}}"}]
      }
    end

    resp =
      LinearMcp.handle_request(
        %{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{"name" => "linear_graphql", "arguments" => %{"query" => "query { viewer { id } }"}}
        },
        tool_executor: executor
      )

    assert resp["result"]["isError"] == false
    assert [%{"type" => "text", "text" => "{\"data\":{}}"}] = resp["result"]["content"]
  end

  test "tools/call failure marks isError true" do
    executor = fn _name, _args -> %{"success" => false, "output" => "boom", "contentItems" => []} end

    resp =
      LinearMcp.handle_request(
        %{"jsonrpc" => "2.0", "id" => 4, "method" => "tools/call", "params" => %{"name" => "linear_graphql", "arguments" => %{}}},
        tool_executor: executor
      )

    assert resp["result"]["isError"] == true
  end

  test "unknown method returns a JSON-RPC error" do
    resp = LinearMcp.handle_request(%{"jsonrpc" => "2.0", "id" => 5, "method" => "nope", "params" => %{}})
    assert resp["error"]["code"] == -32_601
  end
end
