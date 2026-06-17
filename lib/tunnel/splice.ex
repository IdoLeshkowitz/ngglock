defmodule Tunnel.Splice do
  use GenServer, restart: :temporary
  require Logger

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, %{})

  def splice(pid, sock_a, sock_b), do: GenServer.cast(pid, {:splice, sock_a, sock_b})

  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_cast({:splice, a, b}, _state) do
    :ok = ready!(a)
    :ok = ready!(b)
    :ok = :inet.setopts(a, active: :once)
    :ok = :inet.setopts(b, active: :once)
    {:noreply, %{a: a, b: b}}
  end

  @impl true
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

  @impl true
  def handle_info({:tcp_closed, _sock}, state), do: {:stop, :normal, state}

  @impl true
  def handle_info({:tcp_error, _sock, reason}, state) do
    Logger.warning("splice tcp_error: #{inspect(reason)}", reason: inspect(reason))
    {:stop, :normal, state}
  end

  defp ready!(socket) do
    {:ok, [active: false]} = :inet.getopts(socket, [:active])
    {:ok, {_ip, _port}} = :inet.peername(socket)
    :ok
  end
end
