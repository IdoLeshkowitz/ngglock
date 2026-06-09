defmodule Tunnel.Splice do
  use GenServer

  def start_link(sock_a, sock_b) do
    :ok = ready!(sock_a)
    :ok = ready!(sock_b)

    with {:ok, pid} <- GenServer.start_link(__MODULE__, %{a: sock_a, b: sock_b}),
         :ok <- :gen_tcp.controlling_process(sock_a, pid),
         :ok <- :gen_tcp.controlling_process(sock_b, pid) do
      send(pid, :arm)
      {:ok, pid}
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_info(:arm, %{a: a, b: b} = state) do
    :ok = :inet.setopts(a, active: :once)
    :ok = :inet.setopts(b, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp, sock, data}, state) do
    peer = if sock == state.a, do: state.b, else: state.a

    case :gen_tcp.send(peer, data) do
      :ok ->
        :ok = :inet.setopts(sock, active: :once)
        {:noreply, state}

      {:error, _} ->
        {:stop, :normal, state}
    end
  end

  def handle_info({:tcp_closed, _sock}, state), do: {:stop, :normal, state}
  def handle_info({:tcp_error, _sock, _reason}, state), do: {:stop, :normal, state}

  defp ready!(socket) do
    {:ok, [active: false]} = :inet.getopts(socket, [:active])
    {:ok, {_ip, _port}} = :inet.peername(socket)
    :ok
  end
end
