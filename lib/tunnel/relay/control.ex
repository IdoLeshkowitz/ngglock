defmodule Tunnel.Relay.Control do
  use GenServer

  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    %{id: name, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{pid: nil, ref: nil}, name: name)
  end

  def register(server \\ __MODULE__, pid), do: GenServer.cast(server, {:register, pid})

  def send_open(server \\ __MODULE__, token), do: GenServer.call(server, {:send_open, token})

  @impl true
  def init(st), do: {:ok, st}

  @impl true
  def handle_cast({:register, pid}, st) do
    if st.ref, do: Process.demonitor(st.ref, [:flush])
    ref = Process.monitor(pid)
    {:noreply, %{st | pid: pid, ref: ref}}
  end

  @impl true
  def handle_call({:send_open, _token}, _from, %{pid: nil} = st),
    do: {:reply, :no_agent, st}

  def handle_call({:send_open, token}, _from, %{pid: pid} = st) when is_pid(pid) do
    Tunnel.Relay.ControlConnection.send_open(pid, token)
    {:reply, :ok, st}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{ref: ref} = st),
    do: {:noreply, %{st | pid: nil, ref: nil}}
end
