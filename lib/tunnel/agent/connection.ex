defmodule Tunnel.Agent.Connection do
  use GenServer

  @relay_host Application.compile_env!(:tunnel, [Tunnel, :relay_host])
  @tunnel_port Application.compile_env!(:tunnel, [Tunnel, :tunnel_port])
  @local_app_port Application.compile_env!(:tunnel, [Tunnel, :local_app_port])

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %{
      relay_host: opts[:relay_host] || String.to_charlist(@relay_host),
      tunnel_port: opts[:tunnel_port] || @tunnel_port,
      local_app_port: opts[:local_app_port] || @local_app_port,
      backoff: 500,
      ref: nil
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, st) do
    with {:ok, tunnel} <-
           :gen_tcp.connect(st.relay_host, st.tunnel_port, [:binary, active: false]),
         {:ok, local} <-
           :gen_tcp.connect(~c"localhost", st.local_app_port, [:binary, active: false]),
         {:ok, sp} <- DynamicSupervisor.start_child(Tunnel.SpliceSupervisor, Tunnel.Splice),
         :ok <- :gen_tcp.controlling_process(tunnel, sp),
         :ok <- :gen_tcp.controlling_process(local, sp),
         :ok <- Tunnel.Splice.splice(sp, tunnel, local) do
      {:noreply, %{st | ref: Process.monitor(sp)}}
    else
      _ ->
        Process.sleep(st.backoff)
        {:noreply, st, {:continue, :connect}}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{ref: ref} = st),
    do: {:noreply, st, {:continue, :connect}}
end
