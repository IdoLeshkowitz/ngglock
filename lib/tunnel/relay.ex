defmodule Tunnel.Relay do
  def handle_tunnel(socket) do
    :ok = :gen_tcp.controlling_process(socket, Process.whereis(Tunnel.Relay.Tunnels))
    Tunnel.Relay.Tunnels.parked(socket)
  end

  def handle_public(socket) do
    case Tunnel.Relay.Tunnels.checkout(self()) do
      nil ->
        :gen_tcp.close(socket)

      agent ->
        {:ok, sp} = DynamicSupervisor.start_child(Tunnel.SpliceSupervisor, Tunnel.Splice)
        :ok = :gen_tcp.controlling_process(socket, sp)
        :ok = :gen_tcp.controlling_process(agent, sp)
        :ok = Tunnel.Splice.splice(sp, socket, agent)
    end
  end
end
