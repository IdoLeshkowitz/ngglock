defmodule Tunnel.SpliceSupervisor do
  use DynamicSupervisor

  def start_link(_opts \\ []), do: DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)
end
