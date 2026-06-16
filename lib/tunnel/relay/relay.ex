defmodule Tunnel.Relay do
  @token_bytes 16
  @token_timeout 5_000
  @head_timeout 5_000
  @max_head 8192

  def handle_control(socket, sup \\ Tunnel.Relay.ControlConnections, routes \\ Tunnel.Relay.Routes) do
    {:ok, pid} = DynamicSupervisor.start_child(sup, {Tunnel.Relay.ControlConnection, routes: routes})
    Tunnel.Relay.ControlConnection.attach(pid, socket)
  end

  def handle_public(socket, requests \\ Tunnel.Relay.Requests, routes \\ Tunnel.Relay.Routes) do
    head = read_head(socket)

    case Tunnel.Http.subdomain(head) do
      :error ->
        respond(socket, 400)

      {:ok, sub} ->
        case Tunnel.Relay.Routes.whereis(sub, routes) do
          nil ->
            respond(socket, 404)

          ctrl ->
            token = :crypto.strong_rand_bytes(@token_bytes)
            requests_pid = GenServer.whereis(requests)
            :ok = :gen_tcp.controlling_process(socket, requests_pid)
            :ok = Tunnel.Relay.Requests.put(requests, token, {socket, head})
            Tunnel.Relay.ControlConnection.send_open(ctrl, token)
        end
    end
  end

  def handle_proxy(socket, requests \\ Tunnel.Relay.Requests, splice_sup \\ Tunnel.SpliceSupervisor) do
    case :gen_tcp.recv(socket, @token_bytes, @token_timeout) do
      {:ok, token} ->
        case Tunnel.Relay.Requests.take(requests, token, self()) do
          nil ->
            :gen_tcp.close(socket)

          {public, head} ->
            :ok = :gen_tcp.send(socket, head)
            {:ok, sp} = DynamicSupervisor.start_child(splice_sup, Tunnel.Splice)
            :ok = :gen_tcp.controlling_process(public, sp)
            :ok = :gen_tcp.controlling_process(socket, sp)
            :ok = Tunnel.Splice.splice(sp, public, socket)
        end

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp read_head(sock, acc \\ "") do
    cond do
      String.contains?(acc, "\r\n\r\n") ->
        acc

      byte_size(acc) > @max_head ->
        acc

      true ->
        case :gen_tcp.recv(sock, 0, @head_timeout) do
          {:ok, data} -> read_head(sock, acc <> data)
          {:error, _} -> acc
        end
    end
  end

  defp respond(sock, 404) do
    :gen_tcp.send(sock, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    :gen_tcp.close(sock)
  end

  defp respond(sock, 400) do
    :gen_tcp.send(sock, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    :gen_tcp.close(sock)
  end
end
