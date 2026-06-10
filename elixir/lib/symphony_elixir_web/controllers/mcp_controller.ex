defmodule SymphonyElixirWeb.McpController do
  @moduledoc """
  HTTP-транспорт для MCP-инструмента linear_graphql, потребляемого Claude Code.
  Делегирует в SymphonyElixir.Claude.LinearMcp.
  """

  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Claude.LinearMcp
  alias SymphonyElixir.Config

  @spec rpc(Conn.t(), map()) :: Conn.t()
  def rpc(conn, params) do
    if authorized?(conn) do
      json(conn, LinearMcp.handle_request(params))
    else
      conn
      |> put_status(401)
      |> json(%{"jsonrpc" => "2.0", "error" => %{"code" => -32_001, "message" => "Unauthorized"}})
    end
  end

  defp authorized?(conn) do
    case expected_token() do
      nil ->
        true

      token ->
        Conn.get_req_header(conn, "authorization") == ["Bearer #{token}"]
    end
  end

  defp expected_token do
    case safe_config_token() do
      token when is_binary(token) and token != "" -> token
      _ -> blank_to_nil(System.get_env("SYMPHONY_MCP_TOKEN"))
    end
  end

  defp safe_config_token do
    Config.settings!().claude.mcp_token
  rescue
    _ -> nil
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
