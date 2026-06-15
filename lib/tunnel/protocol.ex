defmodule Tunnel.Protocol do
  @open 0x01

  def encode({:open, token}) when is_binary(token), do: <<@open, token::binary>>

  def decode(<<@open, token::binary>>), do: {:open, token}
end
