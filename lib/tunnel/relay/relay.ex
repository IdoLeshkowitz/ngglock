defmodule Tunnel.Relay do
  @token_bytes 16
  @token_timeout 5_000

  def handle_control(
        socket,
        sup \\ Tunnel.Relay.ControlConnections,
        control \\ Tunnel.Relay.Control
      ) do
    {:ok, pid} = DynamicSupervisor.start_child(sup, Tunnel.Relay.ControlConnection)
    Tunnel.Relay.ControlConnection.attach(pid, socket, control)
  end

  def handle_public(socket, requests \\ Tunnel.Relay.Requests, control \\ Tunnel.Relay.Control) do
    token = :crypto.strong_rand_bytes(@token_bytes)
    requests = GenServer.whereis(requests)
    :ok = Tunnel.Relay.Requests.put(requests, token, socket)
    :ok = :gen_tcp.controlling_process(socket, requests)

    case Tunnel.Relay.Control.send_open(control, token) do
      :ok ->
        :ok

      :no_agent ->
        case Tunnel.Relay.Requests.take(requests, token, self()) do
          nil -> :ok
          sock -> :gen_tcp.close(sock)
        end
    end
  end

  def handle_proxy(
        socket,
        requests \\ Tunnel.Relay.Requests,
        splice_sup \\ Tunnel.SpliceSupervisor
      ) do
    case :gen_tcp.recv(socket, @token_bytes, @token_timeout) do
      {:ok, token} ->
        case Tunnel.Relay.Requests.take(requests, token, self()) do
          nil ->
            :gen_tcp.close(socket)

          public ->
            {:ok, sp} = DynamicSupervisor.start_child(splice_sup, Tunnel.Splice)
            :ok = :gen_tcp.controlling_process(public, sp)
            :ok = :gen_tcp.controlling_process(socket, sp)
            :ok = Tunnel.Splice.splice(sp, public, socket)
        end

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end
end
