defmodule Tunnel.ProtocolTest do
  use ExUnit.Case, async: true

  test "round-trips {:open, token}" do
    token = :crypto.strong_rand_bytes(16)
    assert Tunnel.Protocol.decode(Tunnel.Protocol.encode({:open, token})) == {:open, token}
  end
end
