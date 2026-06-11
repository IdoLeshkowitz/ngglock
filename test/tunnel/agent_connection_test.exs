defmodule Tunnel.Agent.ConnectionTest do
  use ExUnit.Case, async: true

  setup do
    n = System.unique_integer([:positive])
    splice_sup = :"splice_sup_#{n}"
    tunnels = :"tunnels_#{n}"

    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup})
    start_supervised!({Tunnel.Relay.Tunnels, name: tunnels})

    {app_port, app_listen} = start_echo_app()
    on_exit(fn -> :gen_tcp.close(app_listen) end)

    %{n: n, splice_sup: splice_sup, tunnels: tunnels, app_port: app_port}
  end

  defp start_tunnel_acceptor(n, tunnels) do
    acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"tunnel_acc_#{n}", 0, fn sock -> Tunnel.Relay.handle_tunnel(tunnels, sock) end}}
      )

    Tunnel.Relay.Acceptor.port(acc)
  end

  defp start_public_acceptor(n, tunnels, splice_sup) do
    acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"public_acc_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_public(tunnels, splice_sup, sock) end}}
      )

    Tunnel.Relay.Acceptor.port(acc)
  end

  defp start_connection(tunnel_port, app_port, splice_sup) do
    start_supervised!(
      {Tunnel.Agent.Connection,
       relay_host: ~c"localhost",
       tunnel_port: tunnel_port,
       local_app_port: app_port,
       splice_supervisor: splice_sup}
    )
  end

  defp start_echo_app do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(l)
    spawn_link(fn -> echo_loop(l) end)
    {port, l}
  end

  defp echo_loop(listen) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        spawn(fn -> echo(sock) end)
        echo_loop(listen)

      _ ->
        :ok
    end
  end

  defp echo(sock) do
    case :gen_tcp.recv(sock, 0, 5000) do
      {:ok, data} ->
        :gen_tcp.send(sock, data)
        echo(sock)

      _ ->
        :gen_tcp.close(sock)
    end
  end

  defp wait_for_parked(tunnels, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn -> Process.sleep(50) end)
    |> Enum.reduce_while(:ok, fn _, _ ->
      if System.monotonic_time(:millisecond) > deadline do
        {:halt, :timeout}
      else
        q = :sys.get_state(tunnels)
        if :queue.is_empty(q), do: {:cont, :ok}, else: {:halt, :ok}
      end
    end)
    |> case do
      :ok -> :ok
      :timeout -> flunk("timed out waiting for agent to park")
    end
  end

  test "connects and parks a tunnel socket on start", %{
    n: n,
    tunnels: tunnels,
    splice_sup: splice_sup,
    app_port: app_port
  } do
    tp = start_tunnel_acceptor(n, tunnels)
    start_connection(tp, app_port, splice_sup)

    assert :ok = wait_for_parked(tunnels)
  end

  test "reconnects after splice exits so a second request succeeds",
       %{n: n, tunnels: tunnels, splice_sup: splice_sup, app_port: app_port} do
    tp = start_tunnel_acceptor(n, tunnels)
    pp = start_public_acceptor(n, tunnels, splice_sup)
    start_connection(tp, app_port, splice_sup)

    for _request <- 1..2 do
      :ok = wait_for_parked(tunnels)

      {:ok, client} = :gen_tcp.connect(~c"localhost", pp, [:binary, active: false])
      :ok = :gen_tcp.send(client, "ping")
      assert {:ok, "ping"} = :gen_tcp.recv(client, 4, 1000)
      :gen_tcp.close(client)
    end
  end

  test "retries until relay becomes available",
       %{n: n, tunnels: tunnels, splice_sup: splice_sup, app_port: app_port} do
    pp = start_public_acceptor(n, tunnels, splice_sup)

    # Hold tmp open so the port can't be stolen while the agent is retrying
    {:ok, tmp} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, future_port} = :inet.port(tmp)

    start_connection(future_port, app_port, splice_sup)

    # Give the connection one backoff cycle to confirm it's alive and still retrying
    Process.sleep(100)
    assert :queue.is_empty(:sys.get_state(tunnels))

    # Release the placeholder and immediately bind the real acceptor — no race window
    :gen_tcp.close(tmp)

    start_supervised!(
      {Tunnel.Relay.Acceptor,
       {:"tunnel_retry_#{n}", future_port,
        fn sock -> Tunnel.Relay.handle_tunnel(tunnels, sock) end}}
    )

    :ok = wait_for_parked(tunnels)

    {:ok, client} = :gen_tcp.connect(~c"localhost", pp, [:binary, active: false])
    :ok = :gen_tcp.send(client, "ping")
    assert {:ok, "ping"} = :gen_tcp.recv(client, 4, 1000)
    :gen_tcp.close(client)
  end
end
