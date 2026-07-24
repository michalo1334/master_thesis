defmodule NetworkDefense.Observability.LogValue do
  @moduledoc false

  def normalize(value) when is_binary(value) do
    if String.valid?(value) and String.printable?(value) do
      value
    else
      %{encoding: "base64", value: Base.encode64(value)}
    end
  end

  def normalize(value) when is_boolean(value) or is_nil(value), do: value
  def normalize(value) when is_atom(value), do: Atom.to_string(value)
  def normalize(value) when is_number(value), do: value
  def normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def normalize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def normalize(%Date{} = value), do: Date.to_iso8601(value)
  def normalize(%Time{} = value), do: Time.to_iso8601(value)
  def normalize(%Decimal{} = value), do: Decimal.to_string(value)

  def normalize(value) when is_list(value) do
    cond do
      List.improper?(value) ->
        inspect(value)

      List.ascii_printable?(value) ->
        List.to_string(value)

      true ->
        Enum.map(value, &normalize/1)
    end
  end

  def normalize(value) when is_tuple(value), do: value |> Tuple.to_list() |> normalize()

  def normalize(value)
      when is_pid(value) or is_port(value) or is_reference(value) or is_function(value),
      do: inspect(value)

  def normalize(%{__struct__: _} = value), do: value |> Map.from_struct() |> normalize()

  def normalize(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {normalize_key(key), normalize(nested_value)} end)
  end

  def normalize(value), do: inspect(value)

  defp normalize_key(key) when is_binary(key), do: normalize(key)
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: inspect(key)
end
