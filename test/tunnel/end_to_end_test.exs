defmodule Tunnel.EndToEndTest do
  use ExUnit.Case, async: false

  defp start_local_app do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(l)
    spawn_link(fn -> local_app_loop(l) end)
    {port, l}
  end

  defp local_app_loop(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        spawn(fn ->
          :gen_tcp.recv(sock, 0, 5000)
          body = "hello"

          resp =
            "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"

          :gen_tcp.send(sock, resp)
          :gen_tcp.close(sock)
        end)

        local_app_loop(listen)

      _ ->
        :ok
    end
  end

  defp wait_for_parked(timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_parked(deadline)
  end

  defp do_wait_parked(deadline) do
    q = :sys.get_state(Tunnel.Relay.Tunnels)

    if :queue.is_empty(q) do
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(50)
        do_wait_parked(deadline)
      else
        flunk("timed out waiting for agent to park a connection")
      end
    else
      :ok
    end
  end

  test "request is served end-to-end through the tunnel" do
    {app_port, app_listen} = start_local_app()

    start_supervised!(Tunnel.SpliceSupervisor)
    start_supervised!(Tunnel.Relay.Tunnels)

    tunnel_acceptor =
      start_supervised!(
        {Tunnel.Relay.Acceptor, {:e2e_tunnel_listener, 0, &Tunnel.Relay.handle_tunnel/1}}
      )

    public_acceptor =
      start_supervised!(
        {Tunnel.Relay.Acceptor, {:e2e_public_listener, 0, &Tunnel.Relay.handle_public/1}}
      )

    tunnel_port = Tunnel.Relay.Acceptor.port(tunnel_acceptor)
    public_port = Tunnel.Relay.Acceptor.port(public_acceptor)

    start_supervised!(
      {Tunnel.Agent.Connection,
       relay_host: ~c"localhost", tunnel_port: tunnel_port, local_app_port: app_port}
    )

    :ok = wait_for_parked()

    {:ok, client} = :gen_tcp.connect(~c"localhost", public_port, [:binary, active: false])
    :ok = :gen_tcp.send(client, "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")

    response = recv_all(client, "")

    assert response =~ "200"
    assert response =~ "hello"

    :gen_tcp.close(client)
    :gen_tcp.close(app_listen)
  end

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, 3000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, :closed} -> acc
      {:error, _} -> acc
    end
  end
end
