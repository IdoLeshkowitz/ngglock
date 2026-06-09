defmodule Tunnel.SpliceTest do
  use ExUnit.Case, async: true

  defp pair do
    {:ok, l} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(l)
    {:ok, client} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    {:ok, server} = :gen_tcp.accept(l)
    :gen_tcp.close(l)
    {client, server}
  end

  test "forwards both directions" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    {:ok, _} = Tunnel.Splice.start_link(s1, s2)

    :ok = :gen_tcp.send(c1, "hello")
    assert {:ok, "hello"} = :gen_tcp.recv(c2, 5, 1000)

    :ok = :gen_tcp.send(c2, "world")
    assert {:ok, "world"} = :gen_tcp.recv(c1, 5, 1000)
  end

  test "closing one side closes the other and splice exits normal" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    {:ok, splice} = Tunnel.Splice.start_link(s1, s2)
    ref = Process.monitor(splice)

    :ok = :gen_tcp.close(c1)
    assert {:error, :closed} = :gen_tcp.recv(c2, 0, 1000)
    assert_receive {:DOWN, ^ref, :process, ^splice, :normal}, 1000
  end

  test "large payload arrives intact" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    {:ok, _} = Tunnel.Splice.start_link(s1, s2)

    payload = :crypto.strong_rand_bytes(1_000_000)
    :ok = :gen_tcp.send(c1, payload)

    received = recv_all(c2, byte_size(payload), [])
    assert received == payload
  end

  test "rejects a non-passive socket" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    :inet.setopts(s2, active: true)

    assert_raise MatchError, fn ->
      Tunnel.Splice.start_link(s1, s2)
    end

    :gen_tcp.close(c1)
    :gen_tcp.close(c2)
  end

  test "rejects an unconnected socket" do
    {c1, s1} = pair()
    {:ok, unconnected} = :gen_tcp.listen(0, [:binary, active: false])

    assert_raise MatchError, fn ->
      Tunnel.Splice.start_link(s1, unconnected)
    end

    :gen_tcp.close(c1)
    :gen_tcp.close(unconnected)
  end

  defp recv_all(sock, remaining, acc) when remaining > 0 do
    chunk = min(remaining, 65_536)
    {:ok, data} = :gen_tcp.recv(sock, chunk, 5000)
    recv_all(sock, remaining - byte_size(data), [acc | data])
  end

  defp recv_all(_sock, 0, acc), do: IO.iodata_to_binary(acc)
end
