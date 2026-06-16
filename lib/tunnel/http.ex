defmodule Tunnel.Http do
  @spec subdomain(binary) :: {:ok, binary} | :error
  def subdomain(head) do
    with {:ok, host} <- extract_host(head) do
      host_no_port = host |> String.split(":") |> hd()
      {:ok, host_no_port |> String.split(".") |> hd()}
    end
  end

  defp extract_host(head) do
    result =
      head
      |> String.split("\r\n")
      |> Enum.find_value(:error, fn line ->
        case String.downcase(line) do
          "host: " <> rest -> {:ok, String.trim(rest)}
          _ -> nil
        end
      end)

    case result do
      :error -> :error
      val -> val
    end
  end
end
