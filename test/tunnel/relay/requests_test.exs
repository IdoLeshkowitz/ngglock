defmodule Tunnel.Relay.RequestsTest do
  use ExUnit.Case, async: true

  setup do
    n = System.unique_integer([:positive])
    name = :"requests_#{n}"
    start_supervised!({Tunnel.Relay.Requests, name: name})
    %{requests: name}
  end

  test "put then take returns correct {socket, head} and removes it", %{requests: req} do
    {:ok, l1} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, l2} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, p1} = :inet.port(l1)
    {:ok, p2} = :inet.port(l2)
    {:ok, s1} = :gen_tcp.connect(~c"localhost", p1, [:binary, active: false])
    {:ok, s2} = :gen_tcp.connect(~c"localhost", p2, [:binary, active: false])

    t1 = :crypto.strong_rand_bytes(16)
    t2 = :crypto.strong_rand_bytes(16)

    req_pid = GenServer.whereis(req)
    :ok = :gen_tcp.controlling_process(s1, req_pid)
    :ok = :gen_tcp.controlling_process(s2, req_pid)

    Tunnel.Relay.Requests.put(req, t1, {s1, "head1"})
    Tunnel.Relay.Requests.put(req, t2, {s2, "head2"})

    assert Tunnel.Relay.Requests.take(req, t1, self()) == {s1, "head1"}
    assert Tunnel.Relay.Requests.take(req, t2, self()) == {s2, "head2"}

    assert Tunnel.Relay.Requests.take(req, t1, self()) == nil

    :gen_tcp.close(l1)
    :gen_tcp.close(l2)
    :gen_tcp.close(s1)
    :gen_tcp.close(s2)
  end

  test "take of unknown token returns nil", %{requests: req} do
    unknown = :crypto.strong_rand_bytes(16)
    assert Tunnel.Relay.Requests.take(req, unknown, self()) == nil
  end

  @park_timeout Application.compile_env!(:tunnel, [Tunnel, :park_timeout])

  test "parked socket is expired and closed when not taken", %{requests: req} do
    {:ok, server_listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(server_listen)
    {:ok, client} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(server_listen)

    req_pid = GenServer.whereis(req)
    :ok = :gen_tcp.controlling_process(server, req_pid)

    token = :crypto.strong_rand_bytes(16)
    Tunnel.Relay.Requests.put(req, token, {server, "head"})

    # Wait for expiry
    Process.sleep(@park_timeout + 100)

    # Entry removed
    assert Tunnel.Relay.Requests.take(req, token, self()) == nil
    # Client end sees the server was closed
    assert :gen_tcp.recv(client, 0, 500) == {:error, :closed}

    :gen_tcp.close(client)
    :gen_tcp.close(server_listen)
  end

  test "take cancels the expiry timer so socket stays open", %{requests: req} do
    {:ok, server_listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(server_listen)
    {:ok, client} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(server_listen)

    req_pid = GenServer.whereis(req)
    :ok = :gen_tcp.controlling_process(server, req_pid)

    token = :crypto.strong_rand_bytes(16)
    Tunnel.Relay.Requests.put(req, token, {server, "head"})

    # Take before expiry
    assert {^server, "head"} = Tunnel.Relay.Requests.take(req, token, self())

    # Wait past park_timeout — no spurious close since we took it
    Process.sleep(@park_timeout + 100)

    # Socket still open
    assert :gen_tcp.recv(client, 0, 100) == {:error, :timeout}

    :gen_tcp.close(server)
    :gen_tcp.close(client)
    :gen_tcp.close(server_listen)
  end
end
