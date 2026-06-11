defmodule Tunnel.EndToEndTest do
  use ExUnit.Case, async: true

  setup do
    n = System.unique_integer([:positive])
    splice_sup = :"splice_sup_e2e_#{n}"
    tunnels = :"tunnels_e2e_#{n}"

    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup})
    start_supervised!({Tunnel.Relay.Tunnels, name: tunnels})

    tunnel_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"tunnel_e2e_#{n}", 0, fn sock -> Tunnel.Relay.handle_tunnel(tunnels, sock) end}}
      )

    public_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"public_e2e_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_public(tunnels, splice_sup, sock) end}}
      )

    tunnel_port = Tunnel.Relay.Acceptor.port(tunnel_acc)
    public_port = Tunnel.Relay.Acceptor.port(public_acc)

    {app_port, app_listen} = start_local_app()
    on_exit(fn -> :gen_tcp.close(app_listen) end)

    start_supervised!(
      {Tunnel.Agent.Connection,
       relay_host: ~c"localhost",
       tunnel_port: tunnel_port,
       local_app_port: app_port,
       splice_supervisor: splice_sup}
    )

    %{tunnels: tunnels, public_port: public_port}
  end

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

  defp wait_for_parked(tunnels, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_parked(tunnels, deadline)
  end

  defp do_wait_parked(tunnels, deadline) do
    q = :sys.get_state(tunnels)

    if :queue.is_empty(q) do
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(50)
        do_wait_parked(tunnels, deadline)
      else
        flunk("timed out waiting for agent to park a connection")
      end
    else
      :ok
    end
  end

  test "request is served end-to-end through the tunnel", %{tunnels: tunnels, public_port: pp} do
    :ok = wait_for_parked(tunnels)

    {:ok, client} = :gen_tcp.connect(~c"localhost", pp, [:binary, active: false])
    :ok = :gen_tcp.send(client, "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")

    response = recv_all(client, "")

    assert response =~ "200"
    assert response =~ "hello"

    :gen_tcp.close(client)
  end

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, 3000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, :closed} -> acc
      {:error, _} -> acc
    end
  end
end
