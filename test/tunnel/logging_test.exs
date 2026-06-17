defmodule Tunnel.LoggingTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  # ── 1. Agent connect failure logs a warning ───────────────────────────────

  test "agent control connect failure logs a warning with relay target" do
    # Find a port that's guaranteed closed
    {:ok, l} = :gen_tcp.listen(0, [:binary])
    {:ok, closed_port} = :inet.port(l)
    :gen_tcp.close(l)

    n = System.unique_integer([:positive])
    proxies = :"proxies_log_#{n}"
    splice_sup = :"splice_sup_log_#{n}"
    start_supervised!({Task.Supervisor, name: proxies})
    start_supervised!({Tunnel.SpliceSupervisor, name: splice_sup})

    log =
      capture_log([level: :warning], fn ->
        pid =
          start_supervised!(
            {Tunnel.Agent.Control,
             relay_host: ~c"localhost",
             control_port: closed_port,
             proxy_port: closed_port,
             local_app_port: 0,
             subdomain: "logtest",
             proxies: proxies,
             splice_supervisor: splice_sup}
          )

        # Give it a moment to attempt connection
        Process.sleep(150)
        Process.exit(pid, :kill)
        Process.sleep(50)
      end)

    assert log =~ "control connect failed"
    assert log =~ "localhost"
  end

  # ── 2. Local app unreachable logs an error and doesn't crash ─────────────

  test "local app unreachable logs an error and returns without raising" do
    # Start a throwaway TCP listener to act as proxy endpoint
    {:ok, proxy_listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, proxy_port} = :inet.port(proxy_listen)

    # Find a closed port for the local app
    {:ok, l} = :gen_tcp.listen(0, [:binary])
    {:ok, dead_local_port} = :inet.port(l)
    :gen_tcp.close(l)

    # Accept one connection on the fake proxy listener
    accept_task =
      Task.async(fn ->
        :gen_tcp.accept(proxy_listen, 5_000)
      end)

    cfg = %{
      relay_host: ~c"localhost",
      proxy_port: proxy_port,
      local_app_port: dead_local_port,
      splice_supervisor: Tunnel.SpliceSupervisor
    }

    token = :crypto.strong_rand_bytes(16)

    log =
      capture_log([level: :error], fn ->
        Tunnel.Agent.Proxy.open(token, cfg)
      end)

    assert log =~ "local app unreachable"
    assert log =~ "localhost:#{dead_local_port}"

    Task.shutdown(accept_task, :brutal_kill)
    :gen_tcp.close(proxy_listen)
  end

  # ── 3. Unknown token logs a warning ──────────────────────────────────────

  test "handle_proxy with unknown token logs a warning" do
    n = System.unique_integer([:positive])
    requests = :"requests_log_#{n}"
    start_supervised!({Tunnel.Relay.Requests, name: requests})

    {:ok, server_listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(server_listen)

    task =
      Task.async(fn ->
        {:ok, sock} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
        bogus_token = :crypto.strong_rand_bytes(16)
        :gen_tcp.send(sock, bogus_token)
        :gen_tcp.close(sock)
      end)

    {:ok, sock} = :gen_tcp.accept(server_listen, 2_000)

    log =
      capture_log([level: :warning], fn ->
        Tunnel.Relay.handle_proxy(sock, requests, Tunnel.SpliceSupervisor)
      end)

    assert log =~ "unknown"
    Task.await(task)
    :gen_tcp.close(server_listen)
  end

  # ── 4. Parked request expiry logs a warning ───────────────────────────────

  @park_timeout Application.compile_env!(:tunnel, [Tunnel, :park_timeout])

  test "parked request expiry logs a warning with token_id" do
    n = System.unique_integer([:positive])
    requests = :"requests_log_exp_#{n}"
    start_supervised!({Tunnel.Relay.Requests, name: requests})

    {:ok, server_listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(server_listen)
    {:ok, client} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(server_listen)

    req_pid = GenServer.whereis(requests)
    :ok = :gen_tcp.controlling_process(server, req_pid)

    token = :crypto.strong_rand_bytes(16)

    log =
      capture_log([level: :warning], fn ->
        Tunnel.Relay.Requests.put(requests, token, {server, "head"})
        Process.sleep(@park_timeout + 100)
      end)

    assert log =~ "parked request expired"
    assert log =~ "token_id"

    :gen_tcp.close(client)
    :gen_tcp.close(server_listen)
  end
end
