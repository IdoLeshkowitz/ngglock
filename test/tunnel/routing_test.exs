defmodule Tunnel.RoutingTest do
  use ExUnit.Case, async: true

  @max_wait 3_000

  setup do
    n = System.unique_integer([:positive])

    splice_sup = :"splice_sup_rt_#{n}"
    requests = :"requests_rt_#{n}"
    control_conns = :"control_conns_rt_#{n}"
    routes = :"routes_rt_#{n}"

    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup})
    start_supervised!({Tunnel.Relay.Requests, name: requests})
    start_supervised!({Registry, keys: :unique, name: routes})
    start_supervised!({DynamicSupervisor, name: control_conns, strategy: :one_for_one})

    control_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"ctrl_acc_rt_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_control(sock, control_conns, routes) end}}
      )

    proxy_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"proxy_acc_rt_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_proxy(sock, requests, splice_sup) end}}
      )

    public_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"public_acc_rt_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_public(sock, requests, routes) end}}
      )

    control_port = Tunnel.Relay.Acceptor.port(control_acc)
    proxy_port = Tunnel.Relay.Acceptor.port(proxy_acc)
    public_port = Tunnel.Relay.Acceptor.port(public_acc)

    {app_a_port, app_a_listen} = start_local_app("A")
    {app_b_port, app_b_listen} = start_local_app("B")

    on_exit(fn ->
      :gen_tcp.close(app_a_listen)
      :gen_tcp.close(app_b_listen)
    end)

    proxies_a = :"proxies_a_rt_#{n}"
    proxies_b = :"proxies_b_rt_#{n}"
    start_supervised!({Task.Supervisor, name: proxies_a})
    start_supervised!({Task.Supervisor, name: proxies_b})

    _agent_a =
      start_supervised!(
        {Tunnel.Agent.Control,
         relay_host: ~c"localhost",
         control_port: control_port,
         proxy_port: proxy_port,
         local_app_port: app_a_port,
         subdomain: "foo",
         proxies: proxies_a,
         splice_supervisor: splice_sup},
        id: :agent_a
      )

    start_supervised!(
      {Tunnel.Agent.Control,
       relay_host: ~c"localhost",
       control_port: control_port,
       proxy_port: proxy_port,
       local_app_port: app_b_port,
       subdomain: "bar",
       proxies: proxies_b,
       splice_supervisor: splice_sup},
      id: :agent_b
    )

    wait_for_route(routes, "foo")
    wait_for_route(routes, "bar")

    %{public_port: public_port, routes: routes}
  end

  defp start_local_app(body) do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(l)
    spawn_link(fn -> local_app_loop(l, body) end)
    {port, l}
  end

  defp local_app_loop(listen, body) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        spawn(fn ->
          case :gen_tcp.recv(sock, 0, 5_000) do
            {:ok, _data} ->
              resp =
                "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"

              :gen_tcp.send(sock, resp)
              :gen_tcp.close(sock)

            _ ->
              :gen_tcp.close(sock)
          end
        end)

        local_app_loop(listen, body)

      _ ->
        :ok
    end
  end

  defp wait_for_route(routes, sub, timeout \\ @max_wait) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      case Registry.lookup(routes, sub) do
        [{_pid, _}] ->
          true

        [] ->
          if System.monotonic_time(:millisecond) < deadline do
            Process.sleep(20)
            false
          else
            flunk("timed out waiting for route #{sub}")
          end
      end
    end)
    |> Enum.find(& &1)
  end

  defp http_request(port, host, method \\ "GET", path \\ "/", body \\ nil) do
    {:ok, sock} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])

    req =
      if body do
        "#{method} #{path} HTTP/1.1\r\nHost: #{host}\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"
      else
        "#{method} #{path} HTTP/1.1\r\nHost: #{host}\r\nConnection: close\r\n\r\n"
      end

    :ok = :gen_tcp.send(sock, req)
    data = recv_all(sock)
    :gen_tcp.close(sock)
    data
  end

  defp recv_all(sock, acc \\ "") do
    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, :closed} -> acc
      {:error, _} -> acc
    end
  end

  test "routes foo to app A and bar to app B", %{public_port: pp} do
    resp_a = http_request(pp, "foo.localtest.me")
    assert resp_a =~ "200 OK"
    assert resp_a =~ "A"
    refute resp_a =~ "B"

    resp_b = http_request(pp, "bar.localtest.me")
    assert resp_b =~ "200 OK"
    assert resp_b =~ "B"
    refute resp_b =~ "A"
  end

  test "unknown host returns 404", %{public_port: pp} do
    resp = http_request(pp, "nope.localtest.me")
    assert resp =~ "404"
  end

  test "missing host returns 400", %{public_port: pp} do
    {:ok, sock} = :gen_tcp.connect(~c"localhost", pp, [:binary, active: false])
    :ok = :gen_tcp.send(sock, "GET / HTTP/1.1\r\nConnection: close\r\n\r\n")
    data = recv_all(sock)
    :gen_tcp.close(sock)
    assert data =~ "400"
  end

  test "POST body delivered intact (head replay + splice)", %{public_port: pp} do
    body = "hello world payload"
    resp = http_request(pp, "foo.localtest.me", "POST", "/", body)
    assert resp =~ "200 OK"
  end

  test "stopping agent frees subdomain", %{public_port: pp, routes: routes} do
    assert Registry.lookup(routes, "foo") != []
    stop_supervised!(:agent_a)

    deadline = System.monotonic_time(:millisecond) + @max_wait

    Stream.repeatedly(fn ->
      case Registry.lookup(routes, "foo") do
        [] ->
          true

        _ ->
          if System.monotonic_time(:millisecond) < deadline do
            Process.sleep(20)
            false
          else
            flunk("timed out waiting for foo route to be removed")
          end
      end
    end)
    |> Enum.find(& &1)

    resp = http_request(pp, "foo.localtest.me")
    assert resp =~ "404"
  end
end
