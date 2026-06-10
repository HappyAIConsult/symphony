defmodule SymphonyElixir.UUIDTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.UUID

  test "v4/0 returns a canonical lowercase UUID v4 string" do
    uuid = UUID.v4()

    assert uuid =~
             ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end

  test "v4/0 produces unique values" do
    refute UUID.v4() == UUID.v4()
  end
end
