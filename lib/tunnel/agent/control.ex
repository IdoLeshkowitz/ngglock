defmodule Tunnel.Agent.Control do
  @behaviour :gen_statem
  require Logger

  @relay_host Application.compile_env!(:tunnel, [Tunnel, :relay_host])
  @control_port Application.compile_env!(:tunnel, [Tunnel, :control_port])
  @proxy_port Application.compile_env!(:tunnel, [Tunnel, :proxy_port])
  @local_app_port Application.compile_env!(:tunnel, [Tunnel, :local_app_port])
  @subdomain Application.compile_env!(:tunnel, [Tunnel, :subdomain])
  @heartbeat_interval Application.compile_env!(:tunnel, [Tunnel, :heartbeat_interval])
  @heartbeat_timeout Application.compile_env!(:tunnel, [Tunnel, :heartbeat_timeout])
  @register_retry Application.compile_env!(:tunnel, [Tunnel, :register_retry])
  @connect_backoff Application.compile_env!(:tunnel, [Tunnel, :connect_backoff])
  @control_packet Application.compile_env!(:tunnel, [Tunnel, :control_packet])

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :permanent}
  end

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      :gen_statem.start_link({:local, name}, __MODULE__, opts, [])
    else
      :gen_statem.start_link(__MODULE__, opts, [])
    end
  end

  @impl :gen_statem
  def callback_mode, do: :state_functions

  @impl :gen_statem
  def init(opts) do
    opts =
      Keyword.validate!(opts,
        relay_host: String.to_charlist(@relay_host),
        control_port: @control_port,
        proxy_port: @proxy_port,
        local_app_port: @local_app_port,
        subdomain: @subdomain,
        proxies: Tunnel.Agent.Proxies,
        splice_supervisor: Tunnel.SpliceSupervisor
      )

    data = %{
      relay_host: Keyword.fetch!(opts, :relay_host),
      control_port: Keyword.fetch!(opts, :control_port),
      proxy_port: Keyword.fetch!(opts, :proxy_port),
      local_app_port: Keyword.fetch!(opts, :local_app_port),
      subdomain: Keyword.fetch!(opts, :subdomain),
      proxies: Keyword.fetch!(opts, :proxies),
      splice_supervisor: Keyword.fetch!(opts, :splice_supervisor),
      socket: nil,
      last_seen: mono(),
      backoff: @connect_backoff
    }

    Logger.info("agent starting subdomain=#{data.subdomain} relay=#{relay_str(data)}",
      subdomain: data.subdomain
    )

    {:ok, :connecting, data, [{:next_event, :internal, :connect}]}
  end

  def connecting(:internal, :connect, data) do
    case :gen_tcp.connect(data.relay_host, data.control_port, [
           :binary,
           active: false,
           packet: @control_packet
         ]) do
      {:ok, sock} ->
        :ok = :gen_tcp.send(sock, Tunnel.Protocol.encode({:register, data.subdomain}))
        :ok = :inet.setopts(sock, active: :once)
        {:next_state, :connected, %{data | socket: sock}}

      {:error, reason} ->
        Logger.warning(
          "control connect failed: #{inspect(reason)}; retry in #{data.backoff}ms relay=#{relay_str(data)}",
          reason: inspect(reason),
          relay: relay_str(data)
        )

        {:keep_state_and_data, [{{:timeout, :retry}, data.backoff, nil}]}
    end
  end

  def connecting({:timeout, :retry}, _content, _data) do
    {:keep_state_and_data, [{:next_event, :internal, :connect}]}
  end

  def connected(:info, {:tcp, sock, frame}, data) do
    :ok = :inet.setopts(sock, active: :once)

    case Tunnel.Protocol.decode(frame) do
      {:registered, sub} ->
        Logger.info("tunnel registered subdomain=#{sub}", subdomain: sub)

        {:next_state, :registered, %{data | last_seen: mono()},
         [{:state_timeout, @heartbeat_interval, :heartbeat}]}

      {:error, reason} ->
        Logger.warning(
          "registration rejected subdomain=#{data.subdomain} reason=#{inspect(reason)}; will retry",
          subdomain: data.subdomain,
          reason: inspect(reason)
        )

        {:keep_state_and_data, [{{:timeout, :reregister}, @register_retry, nil}]}

      _ ->
        :keep_state_and_data
    end
  end

  def connected({:timeout, :reregister}, _content, data) do
    :gen_tcp.send(data.socket, Tunnel.Protocol.encode({:register, data.subdomain}))
    {:keep_state_and_data, []}
  end

  def connected(:info, {:tcp_closed, _}, data) do
    Logger.warning("control connection closed, reconnecting subdomain=#{data.subdomain}",
      subdomain: data.subdomain
    )

    {:next_state, :connecting, %{data | socket: nil}, [{:next_event, :internal, :connect}]}
  end

  def connected(:info, {:tcp_error, _, _}, data) do
    {:next_state, :connecting, %{data | socket: nil}, [{:next_event, :internal, :connect}]}
  end

  def registered(:state_timeout, :heartbeat, data) do
    if mono() - data.last_seen > @heartbeat_timeout do
      Logger.warning("no heartbeat from relay, reconnecting subdomain=#{data.subdomain}",
        subdomain: data.subdomain
      )

      :gen_tcp.close(data.socket)
      {:next_state, :connecting, %{data | socket: nil}, [{:next_event, :internal, :connect}]}
    else
      Logger.info("heartbeat ping subdomain=#{data.subdomain}", subdomain: data.subdomain)
      :gen_tcp.send(data.socket, Tunnel.Protocol.encode({:ping}))
      {:keep_state_and_data, [{:state_timeout, @heartbeat_interval, :heartbeat}]}
    end
  end

  def registered(:info, {:tcp, sock, frame}, data) do
    :ok = :inet.setopts(sock, active: :once)

    case Tunnel.Protocol.decode(frame) do
      {:open, token} ->
        Task.Supervisor.start_child(data.proxies, fn -> Tunnel.Agent.Proxy.open(token, data) end)
        {:keep_state, %{data | last_seen: mono()}}

      {:pong} ->
        Logger.info("heartbeat pong subdomain=#{data.subdomain}", subdomain: data.subdomain)
        {:keep_state, %{data | last_seen: mono()}}

      _ ->
        :keep_state_and_data
    end
  end

  def registered(:info, {:tcp_closed, _}, data) do
    Logger.info("tunnel down subdomain=#{data.subdomain}", subdomain: data.subdomain)
    {:next_state, :connecting, %{data | socket: nil}, [{:next_event, :internal, :connect}]}
  end

  def registered(:info, {:tcp_error, _, _}, data) do
    {:next_state, :connecting, %{data | socket: nil}, [{:next_event, :internal, :connect}]}
  end

  defp relay_str(data), do: "#{data.relay_host}:#{data.control_port}"

  defp mono, do: System.monotonic_time(:millisecond)
end
