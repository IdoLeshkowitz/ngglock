defmodule Tunnel.SpliceSupervisor do
  use DynamicSupervisor

  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    %{id: name, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    DynamicSupervisor.start_link(__MODULE__, [], name: name)
  end

  @impl true
  def init(_), do: DynamicSupervisor.init(strategy: :one_for_one)
end
