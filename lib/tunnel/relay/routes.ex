defmodule Tunnel.Relay.Routes do
  def register(subdomain, registry \\ __MODULE__) do
    case Registry.register(registry, subdomain, nil) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _pid}} -> {:error, "taken"}
    end
  end

  def whereis(subdomain, registry \\ __MODULE__) do
    case Registry.lookup(registry, subdomain) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
