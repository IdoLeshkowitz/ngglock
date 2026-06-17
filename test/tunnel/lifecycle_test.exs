defmodule Tunnel.LifecycleTest do
  use ExUnit.Case, async: true

  @control_timeout Application.compile_env!(:tunnel, [Tunnel, :control_timeout])
  @control_packet Application.compile_env!(:tunnel, [Tunnel, :control_packet])

  # ── helpers ─────────────────────────────────────────────────────────────────

  defp start_relay(n) do
    splice_sup = :"splice_sup_lc_#{n}"
    requests = :"requests_lc_#{n}"
    routes = :"routes_lc_#{n}"
    control_conns = :"control_conns_lc_#{n}"

    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup})
    start_supervised!({Tunnel.Relay.Requests, name: requests})
    start_supervised!({Registry, keys: :unique, name: routes})
    start_supervised!({DynamicSupervisor, name: control_conns, strategy: :one_for_one})

    control_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"control_acc_lc_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_control(sock, control_conns, routes) end}}
      )

    proxy_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"proxy_acc_lc_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_proxy(sock, requests, splice_sup) end}}
      )

    public_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"public_acc_lc_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_public(sock, requests, routes) end}}
      )

    %{
      control_port: Tunnel.Relay.Acceptor.port(control_acc),
      proxy_port: Tunnel.Relay.Acceptor.port(proxy_acc),
      public_port: Tunnel.Relay.Acceptor.port(public_acc),
      requests: requests,
      routes: routes,
      splice_sup: splice_sup
    }
  end

  defp start_agent(n, relay, subdomain) do
    proxies = :"proxies_lc_#{n}"
    splice_sup = :"agent_splice_sup_lc_#{n}"
    start_supervised!({Task.Supervisor, name: proxies})
    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup})

    start_supervised!(
      {Tunnel.Agent.Control,
       relay_host: ~c"localhost",
       control_port: relay.control_port,
       proxy_port: relay.proxy_port,
       local_app_port: 0,
       subdomain: subdomain,
       proxies: proxies,
       splice_supervisor: splice_sup}
    )
  end

  defp wait_route(routes, sub, present?, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      found = Registry.lookup(routes, sub) != []

      if found == present? do
        true
      else
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(20)
          false
        else
          flunk("timed out waiting for route #{sub} present=#{present?}")
        end
      end
    end)
    |> Enum.find(& &1)
  end

  defp start_local_echo do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(l)

    spawn_link(fn ->
      case :gen_tcp.accept(l) do
        {:ok, sock} ->
          case :gen_tcp.recv(sock, 0, 5_000) do
            {:ok, _data} ->
              body = "echo"

              resp =
                "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"

              :gen_tcp.send(sock, resp)
              :gen_tcp.close(sock)

            _ ->
              :gen_tcp.close(sock)
          end

        _ ->
          :ok
      end
    end)

    {port, l}
  end

  # ── tests ────────────────────────────────────────────────────────────────────

  test "heartbeat keepalive: agent pings keep relay route alive past control_timeout" do
    n = System.unique_integer([:positive])
    relay = start_relay(n)
    start_agent(n, relay, "keep")
    wait_route(relay.routes, "keep", true)

    # Wait for several multiples of control_timeout — heartbeats should keep route alive
    Process.sleep(@control_timeout * 3 + 50)
    assert Registry.lookup(relay.routes, "keep") != []
  end

  test "idle reap: silent fake agent is reaped after control_timeout" do
    n = System.unique_integer([:positive])
    relay = start_relay(n)

    # Fake agent: connect, register, then go silent (no pings)
    {:ok, sock} =
      :gen_tcp.connect(~c"localhost", relay.control_port, [
        :binary,
        active: false,
        packet: @control_packet
      ])

    :ok = :gen_tcp.send(sock, Tunnel.Protocol.encode({:register, "silent"}))
    {:ok, frame} = :gen_tcp.recv(sock, 0, 2_000)
    assert Tunnel.Protocol.decode(frame) == {:registered, "silent"}

    wait_route(relay.routes, "silent", true)

    # Go silent — relay should reap within control_timeout
    Process.sleep(@control_timeout + @control_timeout)
    assert Registry.lookup(relay.routes, "silent") == []
    :gen_tcp.close(sock)
  end

  test "agent reconnect + re-register: route reappears after relay drops control connection" do
    n = System.unique_integer([:positive])
    relay = start_relay(n)
    start_agent(n, relay, "reconnect")
    wait_route(relay.routes, "reconnect", true)

    # Kill the relay-side ControlConnection — simulates a half-open drop
    [{ctrl_pid, _}] = Registry.lookup(relay.routes, "reconnect")
    ref = Process.monitor(ctrl_pid)
    Process.exit(ctrl_pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^ctrl_pid, _}, 1_000

    # Agent should reconnect and re-register; route comes back
    wait_route(relay.routes, "reconnect", true, 5_000)
  end

  test "in-flight splice self-cleans when proxy connection drops" do
    n = System.unique_integer([:positive])
    relay = start_relay(n)
    {local_port, local_listen} = start_local_echo()
    on_exit(fn -> :gen_tcp.close(local_listen) end)

    proxies = :"proxies_splice_#{n}"
    splice_sup2 = :"splice_sup2_#{n}"
    start_supervised!({Task.Supervisor, name: proxies})
    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup2})

    start_supervised!(
      {Tunnel.Agent.Control,
       relay_host: ~c"localhost",
       control_port: relay.control_port,
       proxy_port: relay.proxy_port,
       local_app_port: local_port,
       subdomain: "splice",
       proxies: proxies,
       splice_supervisor: splice_sup2}
    )

    wait_route(relay.routes, "splice", true)

    # Fire a public request to start a splice
    {:ok, pub_sock} =
      :gen_tcp.connect(~c"localhost", relay.public_port, [:binary, active: false])

    :ok =
      :gen_tcp.send(
        pub_sock,
        "GET / HTTP/1.1\r\nHost: splice.localtest.me\r\nConnection: close\r\n\r\n"
      )

    # Close the public socket (like browser disconnect) — splice should self-clean
    :gen_tcp.close(pub_sock)

    # Give a moment for cleanup
    Process.sleep(200)

    # No lingering splices
    assert DynamicSupervisor.which_children(relay.splice_sup) == []
  end
end
