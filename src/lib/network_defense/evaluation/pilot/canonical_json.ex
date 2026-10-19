defmodule NetworkDefense.Evaluation.Pilot.CanonicalJson do
  @moduledoc false

  # Deterministic JSON for the snapshot byte count.
  #
  # The documented `payload_bytes` rule compares one canonical encoding on
  # insert and on read. Object keys are sorted, arrays keep their order, and
  # floats use the shortest round-trip form. The encoder accepts only JSON
  # values, so a struct or a non-string key never becomes stored evidence.

  @spec encode(term()) :: {:ok, iodata()} | :error
  def encode(value), do: encode_value(value)

  @spec byte_size(term()) :: {:ok, non_neg_integer()} | :error
  def byte_size(value) do
    with {:ok, encoded} <- encode(value), do: {:ok, IO.iodata_length(encoded)}
  end

  defp encode_value(nil), do: {:ok, "null"}
  defp encode_value(true), do: {:ok, "true"}
  defp encode_value(false), do: {:ok, "false"}
  defp encode_value(value) when is_integer(value), do: {:ok, Integer.to_string(value)}

  defp encode_value(value) when is_float(value) do
    {:ok, :erlang.float_to_binary(value, [:short])}
  rescue
    _exception -> :error
  end

  defp encode_value(value) when is_binary(value) do
    case Jason.encode_to_iodata(value) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, _reason} -> :error
    end
  end

  defp encode_value(value) when is_list(value), do: encode_array(value)

  defp encode_value(value) when is_map(value) do
    if is_struct(value), do: :error, else: encode_object(value)
  end

  defp encode_value(_value), do: :error

  defp encode_array(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, encoded} ->
      case encode_value(value) do
        {:ok, item} -> {:cont, {:ok, [item | encoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, ["[", encoded |> Enum.reverse() |> Enum.intersperse(","), "]"]}
      :error -> :error
    end
  end

  defp encode_object(map) do
    keys = Map.keys(map)

    if Enum.all?(keys, &is_binary/1) and length(Enum.uniq(keys)) == length(keys) do
      encode_object_pairs(map, Enum.sort(keys))
    else
      :error
    end
  end

  defp encode_object_pairs(map, keys) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, encoded} ->
      case encode_value(Map.fetch!(map, key)) do
        {:ok, value} -> {:cont, {:ok, [[encode_key(key), ":", value] | encoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, encoded} ->
        {:ok, ["{", encoded |> Enum.reverse() |> Enum.intersperse(","), "}"]}

      :error ->
        :error
    end
  end

  defp encode_key(key) do
    {:ok, encoded} = Jason.encode_to_iodata(key)
    encoded
  end
end
