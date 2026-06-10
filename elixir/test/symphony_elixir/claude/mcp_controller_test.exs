defmodule SymphonyElixirWeb.McpControllerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias SymphonyElixirWeb.McpController

  defp call(body_params, headers \\ []) do
    conn =
      conn(:post, "/mcp", "")
      |> put_private(:phoenix_endpoint, SymphonyElixirWeb.Endpoint)
      |> Map.put(:body_params, body_params)

    conn = Enum.reduce(headers, conn, fn {k, v}, acc -> put_req_header(acc, k, v) end)
    McpController.rpc(conn, body_params)
  end

  test "tools/list returns 200 with the linear_graphql tool" do
    conn = call(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => %{}})
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert [%{"name" => "linear_graphql"}] = body["result"]["tools"]
  end
end
