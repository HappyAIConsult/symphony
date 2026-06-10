defmodule SymphonyElixir.UUID do
  @moduledoc """
  Минимальный генератор UUID версии 4 (без внешних зависимостей).
  """

  @spec v4() :: String.t()
  def v4 do
    <<u0::48, _ver::4, u1::12, _var::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<a::32, b::16, c::16, d::16, e::48>> = <<u0::48, 4::4, u1::12, 2::2, u2::62>>

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
  end
end
