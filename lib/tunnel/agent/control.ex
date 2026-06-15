defmodule Tunnel.Agent.Control do
  use GenServer

  @relay_host Application.compile_env!(:tunnel, [Tunnel, :relay_host])
  @control_port Application.compile_env!(:tunnel, [Tunnel, :control_port])
  @proxy_port Application.compile_env!(:tunnel, [Tunnel, :proxy_port])
  @local_app_port Application.compile_env!(:tunnel, [Tunnel, :local_app_port])

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    opts =
      Keyword.validate!(opts,
        relay_host: String.to_charlist(@relay_host),
        control_port: @control_port,
        proxy_port: @proxy_port,
        local_app_port: @local_app_port,
        proxies: Tunnel.Agent.Proxies,
        splice_supervisor: Tunnel.SpliceSupervisor
      )

    state = %{
      relay_host: Keyword.fetch!(opts, :relay_host),
      control_port: Keyword.fetch!(opts, :control_port),
      proxy_port: Keyword.fetch!(opts, :proxy_port),
      local_app_port: Keyword.fetch!(opts, :local_app_port),
      proxies: Keyword.fetch!(opts, :proxies),
      splice_supervisor: Keyword.fetch!(opts, :splice_supervisor),
      socket: nil,
      backoff: 500
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, st) do
    case :gen_tcp.connect(st.relay_host, st.control_port, [:binary, active: false, packet: 4]) do
      {:ok, sock} ->
        :ok = :inet.setopts(sock, active: :once)
        {:noreply, %{st | socket: sock}}

      {:error, _} ->
        Process.sleep(st.backoff)
        {:noreply, st, {:continue, :connect}}
    end
  end

  @impl true
  def handle_info({:tcp, sock, frame}, st) do
    case Tunnel.Protocol.decode(frame) do
      {:open, token} ->
        Task.Supervisor.start_child(
          st.proxies,
          fn -> Tunnel.Agent.Proxy.open(token, st) end
        )
    end

    :ok = :inet.setopts(sock, active: :once)
    {:noreply, st}
  end

  def handle_info({:tcp_closed, _}, st),
    do: {:noreply, %{st | socket: nil}, {:continue, :connect}}

  def handle_info({:tcp_error, _, _}, st),
    do: {:noreply, %{st | socket: nil}, {:continue, :connect}}
end
