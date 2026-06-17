defmodule Tunnel.Relay.ControlConnection do
  use GenServer, restart: :temporary
  require Logger

  @control_check Application.compile_env!(:tunnel, [Tunnel, :control_check])
  @control_timeout Application.compile_env!(:tunnel, [Tunnel, :control_timeout])
  @control_packet Application.compile_env!(:tunnel, [Tunnel, :control_packet])

  def start_link(opts \\ []) do
    routes = Keyword.get(opts, :routes, Tunnel.Relay.Routes)
    GenServer.start_link(__MODULE__, %{routes: routes})
  end

  def attach(pid, socket) do
    :ok = :gen_tcp.controlling_process(socket, pid)
    GenServer.cast(pid, {:attach, socket})
  end

  def send_open(pid, token), do: GenServer.cast(pid, {:send_open, token})

  @impl true
  def init(st), do: {:ok, st}

  @impl true
  def handle_cast({:attach, sock}, st) do
    :ok = :inet.setopts(sock, packet: @control_packet, active: :once)
    schedule_check()
    {:noreply, Map.merge(st, %{socket: sock, subdomain: nil, last_seen: mono()})}
  end

  @impl true
  def handle_cast({:send_open, token}, %{socket: s} = st) do
    :ok = :gen_tcp.send(s, Tunnel.Protocol.encode({:open, token}))
    {:noreply, st}
  end

  @impl true
  def handle_info({:tcp, sock, frame}, st) do
    st = handle_frame(Tunnel.Protocol.decode(frame), sock, %{st | last_seen: mono()})
    :ok = :inet.setopts(sock, active: :once)
    {:noreply, st}
  end

  @impl true
  def handle_info(:check, st) do
    if mono() - st.last_seen > @control_timeout do
      if st.subdomain do
        Logger.warning("idle reap subdomain=#{st.subdomain}", subdomain: st.subdomain)
      end

      {:stop, :normal, st}
    else
      schedule_check()
      {:noreply, st}
    end
  end

  @impl true
  def handle_info({:tcp_closed, _}, st) do
    if st.subdomain do
      Logger.info("tunnel down subdomain=#{st.subdomain}", subdomain: st.subdomain)
    end

    {:stop, :normal, st}
  end

  @impl true
  def handle_info({:tcp_error, _, _}, st), do: {:stop, :normal, st}

  defp handle_frame({:ping}, sock, st) do
    Logger.info("heartbeat ping subdomain=#{st.subdomain}", subdomain: st.subdomain)
    :gen_tcp.send(sock, Tunnel.Protocol.encode({:pong}))
    st
  end

  defp handle_frame({:register, sub}, sock, st) do
    case Tunnel.Relay.Routes.register(sub, st.routes) do
      :ok ->
        peer = peer_str(sock)
        Logger.info("tunnel up subdomain=#{sub} peer=#{peer}", subdomain: sub, peer: peer)
        :gen_tcp.send(sock, Tunnel.Protocol.encode({:registered, sub}))
        %{st | subdomain: sub}

      {:error, reason} ->
        Logger.info("subdomain taken subdomain=#{sub}", subdomain: sub)
        :gen_tcp.send(sock, Tunnel.Protocol.encode({:error, reason}))
        st
    end
  end

  defp handle_frame(_other, _sock, st), do: st

  defp schedule_check, do: Process.send_after(self(), :check, @control_check)

  defp mono, do: System.monotonic_time(:millisecond)

  defp peer_str(sock) do
    case :inet.peername(sock) do
      {:ok, {ip, port}} -> "#{:inet.ntoa(ip)}:#{port}"
      _ -> "unknown"
    end
  end
end
