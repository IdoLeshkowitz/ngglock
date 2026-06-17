defmodule Tunnel.Relay.ControlConnectionTest do
  use ExUnit.Case, async: true

  @control_packet Application.compile_env!(:tunnel, [Tunnel, :control_packet])

  setup do
    n = System.unique_integer([:positive])
    routes = :"routes_cc_#{n}"
    start_supervised!({Registry, keys: :unique, name: routes})

    {:ok, cc} = start_supervised({Tunnel.Relay.ControlConnection, routes: routes})

    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: @control_packet])
    {:ok, port} = :inet.port(listen)

    {:ok, client} =
      :gen_tcp.connect(~c"localhost", port, [:binary, active: false, packet: @control_packet])

    {:ok, server} = :gen_tcp.accept(listen)

    Tunnel.Relay.ControlConnection.attach(cc, server)

    %{cc: cc, client: client, routes: routes}
  end

  test "register sends :registered and records subdomain", %{
    cc: cc,
    client: client,
    routes: routes
  } do
    :ok = :gen_tcp.send(client, Tunnel.Protocol.encode({:register, "foo"}))
    {:ok, frame} = :gen_tcp.recv(client, 0, 1_000)
    assert Tunnel.Protocol.decode(frame) == {:registered, "foo"}
    assert Tunnel.Relay.Routes.whereis("foo", routes) == cc
  end

  test "duplicate registration sends :error", %{client: client, routes: routes} do
    other =
      spawn(fn ->
        Registry.register(routes, "taken", nil)
        receive do: (:stop -> :ok)
      end)

    ref = Process.monitor(other)

    :ok = :gen_tcp.send(client, Tunnel.Protocol.encode({:register, "taken"}))
    {:ok, frame} = :gen_tcp.recv(client, 0, 1_000)
    assert Tunnel.Protocol.decode(frame) == {:error, "taken"}

    send(other, :stop)
    assert_receive {:DOWN, ^ref, :process, ^other, _}
  end

  test "send_open delivers :open frame to client", %{cc: cc, client: client} do
    token = :crypto.strong_rand_bytes(16)
    Tunnel.Relay.ControlConnection.send_open(cc, token)
    {:ok, frame} = :gen_tcp.recv(client, 0, 1_000)
    assert Tunnel.Protocol.decode(frame) == {:open, token}
  end

  test "tcp_closed stops the process", %{cc: cc, client: client} do
    ref = Process.monitor(cc)
    :gen_tcp.close(client)
    assert_receive {:DOWN, ^ref, :process, ^cc, _}, 1_000
  end
end
