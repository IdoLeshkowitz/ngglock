defmodule Tunnel.Relay.Tunnels do
  use GenServer

  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    %{id: name, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :queue.new(), name: name)
  end

  def parked(server \\ __MODULE__, socket), do: GenServer.cast(server, {:parked, socket})
  def checkout(server \\ __MODULE__, target), do: GenServer.call(server, {:checkout, target})

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
