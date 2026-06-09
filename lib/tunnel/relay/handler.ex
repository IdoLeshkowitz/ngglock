defmodule Tunnel.Relay.Handler do
  use ThousandIsland.Handler
  require Logger

  @impl ThousandIsland.Handler
  def handle_connection(socket, state) do
    {:ok, {ip, port}} = ThousandIsland.Socket.peername(socket)
    ip_str = ip |> Tuple.to_list() |> Enum.join(".")
    Logger.info("accepted connection from #{ip_str}:#{port}")
    {:continue, state}
  end
end
