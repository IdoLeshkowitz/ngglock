defmodule Tunnel.Agent.Proxy do
  require Logger

  def open(token, cfg) do
    with {:ok, proxy} <-
           :gen_tcp.connect(cfg.relay_host, cfg.proxy_port, [:binary, active: false]),
         :ok <- :gen_tcp.send(proxy, token),
         {:ok, local} <- connect_local(proxy, cfg) do
      {:ok, sp} = DynamicSupervisor.start_child(cfg.splice_supervisor, Tunnel.Splice)
      :ok = :gen_tcp.controlling_process(proxy, sp)
      :ok = :gen_tcp.controlling_process(local, sp)
      :ok = Tunnel.Splice.splice(sp, proxy, local)
    else
      {:error, reason} ->
        Logger.warning("proxy setup failed: #{inspect(reason)}", reason: inspect(reason))
    end
  end

  defp connect_local(proxy, cfg) do
    case :gen_tcp.connect(~c"localhost", cfg.local_app_port, [:binary, active: false]) do
      {:ok, local} ->
        {:ok, local}

      {:error, reason} = err ->
        Logger.error(
          "local app unreachable at localhost:#{cfg.local_app_port}: #{inspect(reason)}",
          reason: inspect(reason)
        )

        _ = :gen_tcp.close(proxy)
        err
    end
  end
end
