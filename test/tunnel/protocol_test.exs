defmodule Tunnel.ProtocolTest do
  use ExUnit.Case, async: true

  test "round-trips {:open, token}" do
    token = :crypto.strong_rand_bytes(16)
    assert Tunnel.Protocol.decode(Tunnel.Protocol.encode({:open, token})) == {:open, token}
  end

  test "round-trips {:register, subdomain}" do
    assert Tunnel.Protocol.decode(Tunnel.Protocol.encode({:register, "foo"})) ==
             {:register, "foo"}
  end

  test "round-trips {:registered, subdomain}" do
    assert Tunnel.Protocol.decode(Tunnel.Protocol.encode({:registered, "foo"})) ==
             {:registered, "foo"}
  end

  test "round-trips {:error, reason}" do
    assert Tunnel.Protocol.decode(Tunnel.Protocol.encode({:error, "taken"})) == {:error, "taken"}
  end

  test "function clause error for an unknown message encoding" do
    assert_raise FunctionClauseError, fn ->
      raise Tunnel.Protocol.encode(nil)
    end
  end

  test "function clause error for an unknown opcode decoding" do
    assert_raise FunctionClauseError, fn ->
      raise Tunnel.Protocol.decode(9999)
    end
  end
end
