defmodule Tunnel.Relay.RoutesTest do
  use ExUnit.Case, async: true

  setup do
    n = System.unique_integer([:positive])
    registry = :"routes_test_#{n}"
    start_supervised!({Registry, keys: :unique, name: registry})
    %{registry: registry}
  end

  test "register and whereis two subdomains", %{registry: reg} do
    parent = self()

    pid_a =
      spawn(fn ->
        Tunnel.Relay.Routes.register("foo", reg)
        send(parent, :registered_a)
        receive do: (:stop -> :ok)
      end)

    receive do: (:registered_a -> :ok)

    pid_b =
      spawn(fn ->
        Tunnel.Relay.Routes.register("bar", reg)
        send(parent, :registered_b)
        receive do: (:stop -> :ok)
      end)

    receive do: (:registered_b -> :ok)

    assert Tunnel.Relay.Routes.whereis("foo", reg) == pid_a
    assert Tunnel.Relay.Routes.whereis("bar", reg) == pid_b

    send(pid_a, :stop)
    send(pid_b, :stop)
  end

  test "duplicate registration returns error", %{registry: reg} do
    parent = self()

    pid =
      spawn(fn ->
        Tunnel.Relay.Routes.register("dup", reg)
        send(parent, :registered)
        receive do: (:stop -> :ok)
      end)

    receive do: (:registered -> :ok)

    result = Task.async(fn -> Tunnel.Relay.Routes.register("dup", reg) end) |> Task.await()
    assert result == {:error, "taken"}

    send(pid, :stop)
  end

  test "whereis returns nil for unknown subdomain", %{registry: reg} do
    assert Tunnel.Relay.Routes.whereis("unknown_#{System.unique_integer()}", reg) == nil
  end

  test "auto-cleanup when registering process dies", %{registry: reg} do
    parent = self()

    pid =
      spawn(fn ->
        Tunnel.Relay.Routes.register("dying", reg)
        send(parent, :registered)
        receive do: (:stop -> :ok)
      end)

    receive do: (:registered -> :ok)
    assert Tunnel.Relay.Routes.whereis("dying", reg) == pid

    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}

    # Registry cleanup is async after process death; poll briefly
    deadline = System.monotonic_time(:millisecond) + 500

    Stream.repeatedly(fn ->
      case Tunnel.Relay.Routes.whereis("dying", reg) do
        nil -> true
        _ -> if System.monotonic_time(:millisecond) < deadline, do: (Process.sleep(5); false), else: false
      end
    end)
    |> Enum.find(& &1)

    assert Tunnel.Relay.Routes.whereis("dying", reg) == nil
  end
end
