defmodule Tunnel.Relay.Tunnels do
  use GenServer

  def start_link(_opts \\ []),
    do: GenServer.start_link(__MODULE__, :queue.new(), name: __MODULE__)

  def parked(socket), do: GenServer.cast(__MODULE__, {:parked, socket})
  def checkout(target), do: GenServer.call(__MODULE__, {:checkout, target})

  @impl true
  def init(q), do: {:ok, q}

  @impl true
  def handle_cast({:parked, s}, q), do: {:noreply, :queue.in(s, q)}

  @impl true
  def handle_call({:checkout, target}, _from, q) do
    case :queue.out(q) do
      {{:value, s}, q2} ->
        :ok = :gen_tcp.controlling_process(s, target)
        {:reply, s, q2}

      {:empty, q2} ->
        {:reply, nil, q2}
    end
  end
end
