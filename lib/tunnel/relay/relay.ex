defmodule Tunnel.Relay do
  def handle_tunnel(socket), do: handle_tunnel(Tunnel.Relay.Tunnels, socket)

  def handle_tunnel(tunnels, socket) do
    :ok = :gen_tcp.controlling_process(socket, GenServer.whereis(tunnels))
    Tunnel.Relay.Tunnels.parked(tunnels, socket)
  end

  def handle_public(socket),
    do: handle_public(Tunnel.Relay.Tunnels, Tunnel.SpliceSupervisor, socket)

  def handle_public(tunnels, splice_sup, socket) do
    case Tunnel.Relay.Tunnels.checkout(tunnels, self()) do
      nil ->
        :gen_tcp.close(socket)

      agent ->
        {:ok, sp} = DynamicSupervisor.start_child(splice_sup, Tunnel.Splice)
        :ok = :gen_tcp.controlling_process(socket, sp)
        :ok = :gen_tcp.controlling_process(agent, sp)
        :ok = Tunnel.Splice.splice(sp, socket, agent)
    end
  end
end
