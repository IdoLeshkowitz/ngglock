defmodule Tunnel.Relay.Acceptor do
  use GenServer

  def child_spec({name, port, on_socket}) do
    %{id: name, start: {__MODULE__, :start_link, [name, port, on_socket]}}
  end

  def start_link(name, port, on_socket) do
    GenServer.start_link(__MODULE__, {port, on_socket}, name: name)
  end

  def port(pid), do: GenServer.call(pid, :port)

  @impl true
  def init({port, on_socket}) do
    {:ok, listen} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
    {:ok, bound_port} = :inet.port(listen)
    spawn_link(fn -> accept_loop(listen, on_socket) end)
    {:ok, %{listen: listen, port: bound_port}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  defp accept_loop(listen, on_socket) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        try do
          on_socket.(sock)
        rescue
          _ -> :gen_tcp.close(sock)
        end

        accept_loop(listen, on_socket)

      {:error, :closed} ->
        :ok

      {:error, _} ->
        accept_loop(listen, on_socket)
    end
  end
end
