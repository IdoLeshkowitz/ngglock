defmodule Tunnel.Relay.ControlTest do
  use ExUnit.Case, async: true

  setup do
    n = System.unique_integer([:positive])
    name = :"control_#{n}"
    start_supervised!({Tunnel.Relay.Control, name: name})
    %{control: name}
  end

  test "send_open returns :no_agent when nothing is registered", %{control: ctrl} do
    assert Tunnel.Relay.Control.send_open(ctrl, :crypto.strong_rand_bytes(16)) == :no_agent
  end

  test "send_open returns :ok after a pid is registered", %{control: ctrl} do
    Tunnel.Relay.Control.register(ctrl, self())
    assert Tunnel.Relay.Control.send_open(ctrl, :crypto.strong_rand_bytes(16)) == :ok
  end

  test "send_open returns :no_agent after the registered process dies", %{control: ctrl} do
    pid = spawn(fn -> receive do: (:stop -> :ok) end)
    Tunnel.Relay.Control.register(ctrl, pid)
    assert Tunnel.Relay.Control.send_open(ctrl, :crypto.strong_rand_bytes(16)) == :ok

    send(pid, :stop)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    assert Tunnel.Relay.Control.send_open(ctrl, :crypto.strong_rand_bytes(16)) == :no_agent
  end

  test "registering a new pid replaces the old one", %{control: ctrl} do
    old = spawn(fn -> receive do: (:stop -> :ok) end)
    Tunnel.Relay.Control.register(ctrl, old)
    send(old, :stop)

    new = spawn(fn -> receive do: (:stop -> :ok) end)
    Tunnel.Relay.Control.register(ctrl, new)

    assert Tunnel.Relay.Control.send_open(ctrl, :crypto.strong_rand_bytes(16)) == :ok
    send(new, :stop)
  end
end
