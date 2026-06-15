defmodule Tunnel.Relay.Requests do
  use GenServer

  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    %{id: name, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def put(server \\ __MODULE__, token, socket) do
    GenServer.cast(server, {:put, token, socket})
  end

  def take(server \\ __MODULE__, token, target),
    do: GenServer.call(server, {:take, token, target})

  @impl true
  def init(m), do: {:ok, m}

  @impl true
  def handle_cast({:put, token, sock}, m), do: {:noreply, Map.put(m, token, sock)}

  @impl true
  def handle_call({:take, token, target}, _from, m) do
    case Map.pop(m, token) do
      {nil, m} ->
        {:reply, nil, m}

      {sock, m} ->
        :ok = :gen_tcp.controlling_process(sock, target)
        {:reply, sock, m}
    end
  end
end
