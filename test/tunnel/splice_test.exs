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

  defp start_splice(sock_a, sock_b) do
    {:ok, sp} = Tunnel.Splice.start_link()
    :ok = :gen_tcp.controlling_process(sock_a, sp)
    :ok = :gen_tcp.controlling_process(sock_b, sp)
    :ok = Tunnel.Splice.splice(sp, sock_a, sock_b)
    {:ok, sp}
  end

  test "forwards both directions" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    {:ok, _} = start_splice(s1, s2)

    :ok = :gen_tcp.send(c1, "hello")
    assert {:ok, "hello"} = :gen_tcp.recv(c2, 5, 1000)

    :ok = :gen_tcp.send(c2, "world")
    assert {:ok, "world"} = :gen_tcp.recv(c1, 5, 1000)
  end

  test "closing one side closes the other and splice exits normal" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    {:ok, splice} = start_splice(s1, s2)
    ref = Process.monitor(splice)

    :ok = :gen_tcp.close(c1)
    assert {:error, :closed} = :gen_tcp.recv(c2, 0, 1000)
    assert_receive {:DOWN, ^ref, :process, ^splice, :normal}, 1000
  end

  test "large payload arrives intact" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    {:ok, _} = start_splice(s1, s2)

    payload = :crypto.strong_rand_bytes(1_000_000)
    :ok = :gen_tcp.send(c1, payload)

    received = recv_all(c2, byte_size(payload), [])
    assert received == payload
  end

  test "rejects a non-passive socket" do
    {c1, s1} = pair()
    {c2, s2} = pair()
    :inet.setopts(s2, active: true)

    # Use start (no link) so the crash doesn't kill the test process
    {:ok, sp} = GenServer.start(Tunnel.Splice, %{})
    ref = Process.monitor(sp)
    :ok = :gen_tcp.controlling_process(s1, sp)
    :ok = :gen_tcp.controlling_process(s2, sp)
    :ok = Tunnel.Splice.splice(sp, s1, s2)

    assert_receive {:DOWN, ^ref, :process, ^sp, _}, 1000

    :gen_tcp.close(c1)
    :gen_tcp.close(c2)
  end

  test "rejects an unconnected socket" do
    {c1, s1} = pair()
    {:ok, unconnected} = :gen_tcp.listen(0, [:binary, active: false])

    {:ok, sp} = GenServer.start(Tunnel.Splice, %{})
    ref = Process.monitor(sp)
    :ok = :gen_tcp.controlling_process(s1, sp)
    :ok = Tunnel.Splice.splice(sp, s1, unconnected)

    assert_receive {:DOWN, ^ref, :process, ^sp, _}, 1000

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
