defmodule Tunnel.Relay.ControlConnection do
  use GenServer, restart: :temporary

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
    :ok = :inet.setopts(sock, packet: 4, active: :once)
    {:noreply, Map.merge(st, %{socket: sock, subdomain: nil})}
  end

  def handle_cast({:send_open, token}, %{socket: s} = st) do
    :ok = :gen_tcp.send(s, Tunnel.Protocol.encode({:open, token}))
    {:noreply, st}
  end

  @impl true
  def handle_info({:tcp, sock, frame}, st) do
    st =
      case Tunnel.Protocol.decode(frame) do
        {:register, sub} ->
          case Tunnel.Relay.Routes.register(sub, st.routes) do
            :ok ->
              :gen_tcp.send(sock, Tunnel.Protocol.encode({:registered, sub}))
              %{st | subdomain: sub}

            {:error, reason} ->
              :gen_tcp.send(sock, Tunnel.Protocol.encode({:error, reason}))
              st
          end

        _ ->
          st
      end

    :ok = :inet.setopts(sock, active: :once)
    {:noreply, st}
  end

  def handle_info({:tcp_closed, _}, st), do: {:stop, :normal, st}
  def handle_info({:tcp_error, _, _}, st), do: {:stop, :normal, st}
end
