defmodule Tunnel.Relay.ControlConnectionTest do
  use ExUnit.Case, async: true

  defp start_conn do
    {:ok, pid} = Tunnel.Relay.ControlConnection.start_link()
    pid
  end

  defp loopback_pair do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(l)
    {:ok, client} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(l)
    :gen_tcp.close(l)
    {client, server}
  end

  test "send_open delivers a framed {:open, token} to the peer" do
    {client, server} = loopback_pair()
    n = System.unique_integer([:positive])
    ctrl = :"ctrl_cc_#{n}"
    start_supervised!({Tunnel.Relay.Control, name: ctrl})

    pid = start_conn()
    Tunnel.Relay.ControlConnection.attach(pid, server, ctrl)

    token = :crypto.strong_rand_bytes(16)
    Tunnel.Relay.ControlConnection.send_open(pid, token)

    # client is raw; read the 4-byte length prefix then the body
    {:ok, <<len::32>>} = :gen_tcp.recv(client, 4, 1_000)
    {:ok, body} = :gen_tcp.recv(client, len, 1_000)
    assert Tunnel.Protocol.decode(body) == {:open, token}

    :gen_tcp.close(client)
  end

  test "process stops normally when the peer closes the connection" do
    {client, server} = loopback_pair()
    n = System.unique_integer([:positive])
    ctrl = :"ctrl_cc2_#{n}"
    start_supervised!({Tunnel.Relay.Control, name: ctrl})

    pid = start_conn()
    ref = Process.monitor(pid)
    Tunnel.Relay.ControlConnection.attach(pid, server, ctrl)

    :gen_tcp.close(client)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
  end
end
