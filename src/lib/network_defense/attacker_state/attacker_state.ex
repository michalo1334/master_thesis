defmodule NetworkDefense.AttackerState.AttackerState do
  @moduledoc """
  Tracks the resources currently controlled by an attacker during one simulation.
  """

  @type t :: %__MODULE__{}

  defstruct footholds: MapSet.new(), attempted_actions: MapSet.new()

  def new(initial_foothold_id), do: %__MODULE__{footholds: MapSet.new([initial_foothold_id])}

  def foothold_nodes(state), do: MapSet.to_list(state.footholds)

  def add_foothold(state, host_id), do: %{state | footholds: MapSet.put(state.footholds, host_id)}

  def attempted?(state, action_key), do: MapSet.member?(state.attempted_actions, action_key)

  def mark_attempted(state, action_key) do
    %{state | attempted_actions: MapSet.put(state.attempted_actions, action_key)}
  end

  def to_map(%__MODULE__{} = state) do
    %{
      "footholds" => MapSet.to_list(state.footholds),
      "attempted_actions" =>
        state.attempted_actions
        |> Enum.map(&encode_action_key/1)
    }
  end

  def from_map(%{"footholds" => footholds, "attempted_actions" => attempted_actions})
      when is_list(footholds) and is_list(attempted_actions) do
    with {:ok, attempted_actions} <- decode_action_keys(attempted_actions) do
      {:ok,
       %__MODULE__{
         footholds: MapSet.new(footholds),
         attempted_actions: MapSet.new(attempted_actions)
       }}
    end
  end

  def from_map(_), do: :error

  defp decode_action_keys(action_keys) do
    Enum.reduce_while(action_keys, {:ok, []}, fn
      action_key, {:ok, decoded_keys} ->
        case decode_term(action_key) do
          {:ok, decoded_key} -> {:cont, {:ok, [decoded_key | decoded_keys]}}
          :error -> {:halt, :error}
        end
    end)
    |> case do
      {:ok, decoded_keys} -> {:ok, Enum.reverse(decoded_keys)}
      :error -> :error
    end
  end

  defp encode_action_key(action_key) do
    case encode_term(action_key) do
      {:ok, encoded_key} -> encoded_key
      :error -> raise ArgumentError, "action key is not JSON serializable"
    end
  end

  defp encode_term(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: {:ok, %{"type" => "value", "value" => value}}

  defp encode_term(value) when is_atom(value),
    do: {:ok, %{"type" => "atom", "value" => Atom.to_string(value)}}

  defp encode_term(value) when is_list(value), do: encode_collection("list", value)

  defp encode_term(value) when is_tuple(value),
    do: encode_collection("tuple", Tuple.to_list(value))

  defp encode_term(_), do: :error

  defp encode_collection(type, values) do
    case encode_terms(values) do
      {:ok, encoded_values} -> {:ok, %{"type" => type, "values" => encoded_values}}
      :error -> :error
    end
  end

  defp encode_terms(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, encoded_values} ->
      case encode_term(value) do
        {:ok, encoded_value} -> {:cont, {:ok, [encoded_value | encoded_values]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, encoded_values} -> {:ok, Enum.reverse(encoded_values)}
      :error -> :error
    end
  end

  defp decode_term(%{"type" => "value", "value" => value}), do: {:ok, value}

  defp decode_term(%{"type" => "atom", "value" => value}) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> :error
  end

  defp decode_term(%{"type" => "list", "values" => values}) when is_list(values),
    do: decode_collection(values)

  defp decode_term(%{"type" => "tuple", "values" => values}) when is_list(values) do
    case decode_collection(values) do
      {:ok, values} -> {:ok, List.to_tuple(values)}
      :error -> :error
    end
  end

  defp decode_term(_), do: :error

  defp decode_collection(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, decoded_values} ->
      case decode_term(value) do
        {:ok, decoded_value} -> {:cont, {:ok, [decoded_value | decoded_values]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, decoded_values} -> {:ok, Enum.reverse(decoded_values)}
      :error -> :error
    end
  end
end

defimpl Jason.Encoder, for: NetworkDefense.AttackerState.AttackerState do
  alias NetworkDefense.AttackerState.AttackerState

  def encode(state, opts), do: Jason.Encode.map(AttackerState.to_map(state), opts)
end
