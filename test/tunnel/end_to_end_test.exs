defmodule Tunnel.EndToEndTest do
  use ExUnit.Case, async: true

  setup do
    n = System.unique_integer([:positive])

    splice_sup = :"splice_sup_e2e_#{n}"
    requests = :"requests_e2e_#{n}"
    routes = :"routes_e2e_#{n}"
    control_conns = :"control_conns_e2e_#{n}"

    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup})
    start_supervised!({Tunnel.Relay.Requests, name: requests})
    start_supervised!({Registry, keys: :unique, name: routes})
    start_supervised!({DynamicSupervisor, name: control_conns, strategy: :one_for_one})

    control_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"control_acc_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_control(sock, control_conns, routes) end}}
      )

    proxy_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"proxy_acc_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_proxy(sock, requests, splice_sup) end}}
      )

    public_acc =
      start_supervised!(
        {Tunnel.Relay.Acceptor,
         {:"public_acc_#{n}", 0,
          fn sock -> Tunnel.Relay.handle_public(sock, requests, routes) end}}
      )

    control_port = Tunnel.Relay.Acceptor.port(control_acc)
    proxy_port = Tunnel.Relay.Acceptor.port(proxy_acc)
    public_port = Tunnel.Relay.Acceptor.port(public_acc)

    {app_port, app_listen} = start_local_app()
    on_exit(fn -> :gen_tcp.close(app_listen) end)

    proxies = :"proxies_e2e_#{n}"
    start_supervised!({Task.Supervisor, name: proxies})

    start_supervised!(
      {Tunnel.Agent.Control,
       relay_host: ~c"localhost",
       control_port: control_port,
       proxy_port: proxy_port,
       local_app_port: app_port,
       subdomain: "myapp",
       proxies: proxies,
       splice_supervisor: splice_sup}
    )

    wait_for_route(routes, "myapp")

    %{public_port: public_port, routes: routes}
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
          case :gen_tcp.recv(sock, 0, 5_000) do
            {:ok, data} ->
              path =
                case Regex.run(~r{^GET (\S+)}, data) do
                  [_, p] -> p
                  _ -> data
                end

              body = path

              resp =
                "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"

              :gen_tcp.send(sock, resp)
              :gen_tcp.close(sock)

            _ ->
              :gen_tcp.close(sock)
          end
        end)

        local_app_loop(listen)

      _ ->
        :ok
    end
  end

  defp wait_for_route(routes, sub, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.repeatedly(fn ->
      case Registry.lookup(routes, sub) do
        [{_pid, _}] ->
          true

        [] ->
          if System.monotonic_time(:millisecond) < deadline do
            Process.sleep(50)
            false
          else
            flunk("timed out waiting for route #{sub}")
          end
      end
    end)
    |> Enum.find(& &1)
  end

  defp http_get(port, path) do
    {:ok, sock} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])

    :ok =
      :gen_tcp.send(
        sock,
        "GET #{path} HTTP/1.1\r\nHost: myapp.localtest.me\r\nConnection: close\r\n\r\n"
      )

    data = recv_all(sock, "")
    :gen_tcp.close(sock)
    data
  end

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, 3_000) do
      {:ok, data} -> recv_all(sock, acc <> data)
      {:error, :closed} -> acc
      {:error, _} -> acc
    end
  end

  test "two concurrent requests served without cross-wiring", %{public_port: pp} do
    parent = self()
    spawn(fn -> send(parent, {:a, http_get(pp, "/path-alpha")}) end)
    spawn(fn -> send(parent, {:b, http_get(pp, "/path-beta")}) end)

    results =
      for _ <- 1..2 do
        receive do
          {k, v} -> {k, v}
        after
          5_000 -> flunk("timed out waiting for response")
        end
      end
      |> Map.new()

    assert results.a =~ "/path-alpha"
    assert results.b =~ "/path-beta"
    refute results.a =~ "/path-beta"
    refute results.b =~ "/path-alpha"
  end
end
