defmodule Tunnel.Relay.ControlConnection do
  use GenServer, restart: :temporary

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{})

  def attach(pid, socket, control \\ Tunnel.Relay.Control) do
    :ok = :gen_tcp.controlling_process(socket, pid)
    GenServer.cast(pid, {:attach, socket, control})
  end

  def send_open(pid, token), do: GenServer.cast(pid, {:send_open, token})

  @impl true
  def init(st), do: {:ok, st}

  @impl true
  def handle_cast({:attach, sock, control}, _st) do
    :ok = :inet.setopts(sock, packet: 4, active: :once)
    Tunnel.Relay.Control.register(control, self())
    {:noreply, %{socket: sock}}
  end

  def handle_cast({:send_open, token}, %{socket: s} = st) do
    :ok = :gen_tcp.send(s, Tunnel.Protocol.encode({:open, token}))
    {:noreply, st}
  end

  @impl true
  def handle_info({:tcp, s, _frame}, st) do
    :inet.setopts(s, active: :once)
    {:noreply, st}
  end

  def handle_info({:tcp_closed, _}, st), do: {:stop, :normal, st}
  def handle_info({:tcp_error, _, _}, st), do: {:stop, :normal, st}
end
