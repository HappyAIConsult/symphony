defmodule SymphonyElixir.Claude.LinearMcp do
  @moduledoc """
  Минимальный MCP-сервер (JSON-RPC поверх HTTP) с единственным инструментом
  `linear_graphql`. Делегирует выполнение в Codex.DynamicTool (единый источник
  правды по схеме и логике вызова Linear).
  """

  alias SymphonyElixir.Codex.DynamicTool

  @protocol_version "2025-06-18"

  @spec handle_request(map(), keyword()) :: map()
  def handle_request(request, opts \\ [])

  def handle_request(%{"method" => "initialize", "id" => id}, _opts) do
    ok(id, %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "symphony-linear", "version" => "0.1.0"}
    })
  end

  def handle_request(%{"method" => "tools/list", "id" => id}, _opts) do
    ok(id, %{"tools" => DynamicTool.tool_specs()})
  end

  def handle_request(%{"method" => "tools/call", "id" => id, "params" => params}, opts) do
    executor = Keyword.get(opts, :tool_executor, &DynamicTool.execute/2)
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    result = executor.(name, arguments)
    success = Map.get(result, "success", false)

    content =
      case Map.get(result, "contentItems") do
        items when is_list(items) and items != [] ->
          Enum.map(items, fn item -> %{"type" => "text", "text" => Map.get(item, "text", "")} end)

        _ ->
          [%{"type" => "text", "text" => Map.get(result, "output", "")}]
      end

    ok(id, %{"content" => content, "isError" => not success})
  end

  def handle_request(%{"id" => id}, _opts) do
    error(id, -32_601, "Method not found")
  end

  def handle_request(_request, _opts) do
    error(nil, -32_600, "Invalid Request")
  end

  defp ok(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp error(id, code, message),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
end
