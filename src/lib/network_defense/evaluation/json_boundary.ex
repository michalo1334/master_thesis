defmodule NetworkDefense.Evaluation.JsonBoundary do
  @moduledoc false

  # Shared pre-schema checks for JSON request maps.
  #
  # Each contract supplies its own error constructor so the boundary never
  # guesses which contract produced a value.

  @type error_fun :: ([term()] -> struct())

  @spec string_keys_only(term(), [term()], error_fun()) :: :ok | {:error, struct()}
  def string_keys_only(value, path, on_invalid) when is_map(value) do
    Enum.reduce_while(value, :ok, fn
      {key, nested}, :ok when is_binary(key) ->
        case string_keys_only(nested, path ++ [key], on_invalid) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      {_key, _value}, :ok ->
        {:halt, {:error, on_invalid.(path)}}
    end)
  end

  def string_keys_only(list, path, on_invalid) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case string_keys_only(value, path ++ [index], on_invalid) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def string_keys_only(value, _path, _on_invalid)
      when is_binary(value) or is_boolean(value) or is_number(value) or is_nil(value),
      do: :ok

  def string_keys_only(_value, path, on_invalid), do: {:error, on_invalid.(path)}

  @spec encode(term(), error_fun()) :: {:ok, iodata()} | {:error, struct()}
  def encode(value, on_invalid) do
    case Jason.encode_to_iodata(value) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, _reason} -> {:error, on_invalid.([])}
    end
  rescue
    _exception -> {:error, on_invalid.([])}
  end

  @spec within_limit(iodata(), non_neg_integer(), (non_neg_integer() -> struct())) ::
          :ok | {:error, struct()}
  def within_limit(encoded, limit, on_too_large) do
    if IO.iodata_length(encoded) <= limit do
      :ok
    else
      {:error, on_too_large.(limit)}
    end
  end
end
