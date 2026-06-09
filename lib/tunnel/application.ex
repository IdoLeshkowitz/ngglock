defmodule Tunnel.Application do
  use Application
  require Logger

  @role Application.compile_env!(:tunnel, [Tunnel, :role])
  @tunnel_port Application.compile_env!(:tunnel, [Tunnel, :tunnel_port])
  @public_port Application.compile_env!(:tunnel, [Tunnel, :public_port])

  @impl true
  def start(_type, _args) do
    children = shared_children(@role) ++ role_children(@role)
    Supervisor.start_link(children, strategy: :one_for_one, name: Tunnel.Supervisor)
  end

  defp shared_children(:none), do: []
  defp shared_children(_), do: [Tunnel.SpliceSupervisor]

  defp role_children(:relay) do
    Logger.info("relay tunnel_port=#{@tunnel_port} public_port=#{@public_port}")
    [
      Tunnel.Relay.Tunnels,
      {Tunnel.Relay.Acceptor, {:tunnel_listener, @tunnel_port, &Tunnel.Relay.handle_tunnel/1}},
      {Tunnel.Relay.Acceptor, {:public_listener, @public_port, &Tunnel.Relay.handle_public/1}}
    ]
  end

  defp role_children(:agent), do: [Tunnel.Agent.Connection]
  defp role_children(:all), do: role_children(:relay) ++ role_children(:agent)
  defp role_children(:none), do: []
end
