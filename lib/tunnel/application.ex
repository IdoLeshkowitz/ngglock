defmodule Tunnel.Application do
  use Application
  require Logger

  @role        Application.compile_env!(:tunnel, [Tunnel, :role])
  @listen_port Application.compile_env!(:tunnel, [Tunnel, :listen_port])

  @impl true
  def start(_type, _args) do
    children = shared_children() ++ role_children(@role)
    Supervisor.start_link(children, strategy: :one_for_one, name: Tunnel.Supervisor)
  end

  defp shared_children, do: []

  defp role_children(:relay) do
    Logger.info("relay listening on port #{@listen_port}")
    [{ThousandIsland, port: @listen_port, handler_module: Tunnel.Relay.Handler}]
  end

  defp role_children(:agent), do: []
  defp role_children(:none),  do: []
end
