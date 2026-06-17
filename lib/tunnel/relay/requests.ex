defmodule Tunnel.Relay.Requests do
  use GenServer
  require Logger

  @park_timeout Application.compile_env!(:tunnel, [Tunnel, :park_timeout])

  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    %{id: name, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def put(server \\ __MODULE__, token, {socket, head}) do
    GenServer.cast(server, {:put, token, {socket, head}})
  end

  def take(server \\ __MODULE__, token, target),
    do: GenServer.call(server, {:take, token, target})

  @impl true
  def init(m), do: {:ok, m}

  @impl true
  def handle_cast({:put, token, {socket, head}}, m) do
    ref = Process.send_after(self(), {:expire, token}, @park_timeout)
    {:noreply, Map.put(m, token, {socket, head, ref})}
  end

  @impl true
  def handle_call({:take, token, target}, _from, m) do
    case Map.pop(m, token) do
      {nil, m} ->
        {:reply, nil, m}

      {{sock, head, ref}, m} ->
        Process.cancel_timer(ref)
        :ok = :gen_tcp.controlling_process(sock, target)
        {:reply, {sock, head}, m}
    end
  end

  @impl true
  def handle_info({:expire, token}, m) do
    case Map.pop(m, token) do
      {nil, m} ->
        {:noreply, m}

      {{sock, _head, _ref}, m} ->
        Logger.warning("parked request expired token_id=#{token_id(token)}",
          token_id: token_id(token)
        )

        :gen_tcp.close(sock)
        {:noreply, m}
    end
  end

  defp token_id(token), do: Base.encode16(binary_part(token, 0, 4))
end
