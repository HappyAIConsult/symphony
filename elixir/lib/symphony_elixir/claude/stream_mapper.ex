defmodule SymphonyElixir.Claude.StreamMapper do
  @moduledoc """
  Чистый маппинг событий Claude Code `--output-format stream-json` в словарь
  событий Symphony (как у Codex.AppServer). Без побочных эффектов.
  """

  @type classification ::
          {:event, atom(), map()}
          | {:result, :ok | :error, map()}
          | :ignore

  @limit_markers ["usage limit", "rate limit", "overloaded", "try again later"]

  @spec classify(map()) :: classification()
  def classify(%{"type" => "result"} = decoded) do
    usage = Map.get(decoded, "usage")
    base = %{payload: decoded, usage: usage, subtype: Map.get(decoded, "subtype")}

    if Map.get(decoded, "is_error", false) or limit?(decoded) do
      {:result, :error,
       Map.merge(base, %{
         reason: {:claude_result_error, Map.get(decoded, "subtype"), Map.get(decoded, "result")},
         retryable: limit?(decoded)
       })}
    else
      {:result, :ok,
       Map.merge(base, %{
         result: Map.get(decoded, "result"),
         cost_usd: Map.get(decoded, "total_cost_usd"),
         num_turns: Map.get(decoded, "num_turns")
       })}
    end
  end

  def classify(%{"type" => "assistant", "message" => message} = decoded) when is_map(message) do
    {:event, :notification, %{payload: decoded, usage: Map.get(message, "usage")}}
  end

  def classify(%{"type" => "user", "message" => %{"content" => content}} = decoded)
      when is_list(content) do
    case Enum.find(content, &match?(%{"type" => "tool_result"}, &1)) do
      %{"is_error" => true} ->
        {:event, :tool_call_failed, %{payload: decoded}}

      %{"type" => "tool_result"} ->
        {:event, :tool_call_completed, %{payload: decoded}}

      _ ->
        {:event, :notification, %{payload: decoded}}
    end
  end

  def classify(%{"type" => "system"} = decoded) do
    {:event, :notification, %{payload: decoded}}
  end

  def classify(decoded) when is_map(decoded) do
    {:event, :other_message, %{payload: decoded}}
  end

  @spec limit?(map()) :: boolean()
  def limit?(decoded) when is_map(decoded) do
    text =
      [Map.get(decoded, "result"), Map.get(decoded, "subtype")]
      |> Enum.filter(&is_binary/1)
      |> Enum.map_join(" ", &String.downcase/1)

    Enum.any?(@limit_markers, &String.contains?(text, &1))
  end
end
