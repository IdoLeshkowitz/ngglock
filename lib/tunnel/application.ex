defmodule Tunnel.Application do
  use Application
  require Logger

  @role Application.compile_env!(:tunnel, [Tunnel, :role])
  @control_port Application.compile_env!(:tunnel, [Tunnel, :control_port])
  @proxy_port Application.compile_env!(:tunnel, [Tunnel, :proxy_port])
  @public_port Application.compile_env!(:tunnel, [Tunnel, :public_port])

  @impl true
  def start(_type, _args) do
    children = shared_children() ++ role_children(@role)
    Supervisor.start_link(children, strategy: :one_for_one, name: Tunnel.Supervisor)
  end

  defp shared_children, do: [Tunnel.SpliceSupervisor]

  defp role_children(:relay) do
    Logger.info(
      "relay control_port=#{@control_port} proxy_port=#{@proxy_port} public_port=#{@public_port}"
    )

    [
      Tunnel.Relay.Requests,
      Tunnel.Relay.Control,
      {DynamicSupervisor, name: Tunnel.Relay.ControlConnections, strategy: :one_for_one},
      {Tunnel.Relay.Acceptor, {:control_listener, @control_port, &Tunnel.Relay.handle_control/1}},
      {Tunnel.Relay.Acceptor, {:proxy_listener, @proxy_port, &Tunnel.Relay.handle_proxy/1}},
      {Tunnel.Relay.Acceptor, {:public_listener, @public_port, &Tunnel.Relay.handle_public/1}}
    ]
  end

  defp role_children(:agent) do
    [{Task.Supervisor, name: Tunnel.Agent.Proxies}, Tunnel.Agent.Control]
  end

  defp role_children(:all), do: role_children(:relay) ++ role_children(:agent)
  defp role_children(:none), do: []
end
