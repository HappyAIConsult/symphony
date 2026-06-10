defmodule SymphonyElixir.AgentBackend do
  @moduledoc """
  Контракт агентного бэкенда и резолвер реализации по `agent.kind`.
  Обе реализации (Codex.AppServer, Claude.AppServer) должны соблюдать один
  интерфейс из трёх функций, чтобы AgentRunner работал без изменений логики.
  """

  alias SymphonyElixir.Config

  @type session :: map()

  @callback start_session(workspace :: Path.t(), opts :: keyword()) ::
              {:ok, session()} | {:error, term()}
  @callback run_turn(session(), prompt :: String.t(), issue :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback stop_session(session()) :: :ok

  @spec resolve() :: module()
  def resolve, do: __MODULE__.for(Config.agent_kind())

  @spec for(:codex | :claude) :: module()
  def for(:claude), do: SymphonyElixir.Claude.AppServer
  def for(_), do: SymphonyElixir.Codex.AppServer
end
