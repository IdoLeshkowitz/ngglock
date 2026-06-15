defmodule Tunnel.Agent.Proxy do
  def open(token, cfg) do
    {:ok, proxy} =
      :gen_tcp.connect(cfg.relay_host, cfg.proxy_port, [:binary, active: false])

    :ok = :gen_tcp.send(proxy, token)

    {:ok, local} =
      :gen_tcp.connect(~c"localhost", cfg.local_app_port, [:binary, active: false])

    {:ok, sp} = DynamicSupervisor.start_child(Tunnel.SpliceSupervisor, Tunnel.Splice)
    :ok = :gen_tcp.controlling_process(proxy, sp)
    :ok = :gen_tcp.controlling_process(local, sp)
    :ok = Tunnel.Splice.splice(sp, proxy, local)
  end
end
