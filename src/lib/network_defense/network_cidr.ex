defmodule NetworkDefense.NetworkCidr do
  @moduledoc false

  def valid?(value) when is_binary(value) do
    with [address, prefix] <- String.split(value, "/", parts: 2),
         {prefix, ""} <- Integer.parse(prefix),
         {:ok, address} <- :inet.parse_address(String.to_charlist(address)) do
      prefix in 0..if(tuple_size(address) == 4, do: 32, else: 128)
    else
      _ -> false
    end
  end

  def valid?(_value), do: false
end
