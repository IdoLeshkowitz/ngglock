defmodule Tunnel.Protocol do
  @open 0x01
  @register 0x02
  @registered 0x03
  @error 0x04

  def encode({:open, token}) when is_binary(token), do: <<@open, token::binary>>
  def encode({:register, sub}), do: <<@register, sub::binary>>
  def encode({:registered, sub}), do: <<@registered, sub::binary>>
  def encode({:error, reason}), do: <<@error, reason::binary>>

  def decode(<<@open, token::binary>>), do: {:open, token}
  def decode(<<@register, sub::binary>>), do: {:register, sub}
  def decode(<<@registered, sub::binary>>), do: {:registered, sub}
  def decode(<<@error, reason::binary>>), do: {:error, reason}
end
