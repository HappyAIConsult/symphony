defmodule SymphonyElixir.Claude.StreamMapperTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Claude.StreamMapper

  test "system/init maps to a notification" do
    decoded = %{"type" => "system", "subtype" => "init", "session_id" => "abc", "tools" => []}
    assert {:event, :notification, details} = StreamMapper.classify(decoded)
    assert details.payload == decoded
  end

  test "assistant text maps to a notification" do
    decoded = %{
      "type" => "assistant",
      "message" => %{"content" => [%{"type" => "text", "text" => "hi"}], "usage" => %{"output_tokens" => 3}}
    }

    assert {:event, :notification, details} = StreamMapper.classify(decoded)
    assert details.usage == %{"output_tokens" => 3}
  end

  test "tool_result without error maps to tool_call_completed" do
    decoded = %{
      "type" => "user",
      "message" => %{"content" => [%{"type" => "tool_result", "tool_use_id" => "t1", "is_error" => false}]}
    }

    assert {:event, :tool_call_completed, _details} = StreamMapper.classify(decoded)
  end

  test "tool_result with error maps to tool_call_failed" do
    decoded = %{
      "type" => "user",
      "message" => %{"content" => [%{"type" => "tool_result", "tool_use_id" => "t1", "is_error" => true}]}
    }

    assert {:event, :tool_call_failed, _details} = StreamMapper.classify(decoded)
  end

  test "successful result returns an ok result with usage and text" do
    decoded = %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "result" => "done",
      "usage" => %{"input_tokens" => 10, "output_tokens" => 5},
      "total_cost_usd" => 0.01
    }

    assert {:result, :ok, details} = StreamMapper.classify(decoded)
    assert details.result == "done"
    assert details.usage == %{"input_tokens" => 10, "output_tokens" => 5}
  end

  test "error result returns an error result" do
    decoded = %{"type" => "result", "subtype" => "error_during_execution", "is_error" => true}
    assert {:result, :error, details} = StreamMapper.classify(decoded)
    assert details.subtype == "error_during_execution"
  end

  test "usage-limit result is flagged retryable" do
    decoded = %{
      "type" => "result",
      "subtype" => "error_during_execution",
      "is_error" => true,
      "result" => "Claude usage limit reached. Try again later."
    }

    assert {:result, :error, details} = StreamMapper.classify(decoded)
    assert details.retryable == true
  end
end
