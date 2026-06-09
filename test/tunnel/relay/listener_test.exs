defmodule Tunnel.Relay.ListenerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  test "accepts a connection" do
    pid = start_supervised!({ThousandIsland, port: 0, handler_module: Tunnel.Relay.Handler})
    {:ok, {_addr, port}} = ThousandIsland.listener_info(pid)
    assert {:ok, _sock} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
  end

  test "logs the connection" do
    pid = start_supervised!({ThousandIsland, port: 0, handler_module: Tunnel.Relay.Handler})
    {:ok, {_addr, port}} = ThousandIsland.listener_info(pid)

    assert {:ok, _sock} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
  end
end
