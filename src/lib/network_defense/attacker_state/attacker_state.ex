defmodule NetworkDefense.AttackerState.AttackerState do
  @moduledoc """
  Tracks the resources currently controlled by an attacker during one simulation.
  """

  @type t :: %__MODULE__{}

  defstruct footholds: MapSet.new(),
            attempted_actions: MapSet.new(),
            privileges: %{},
            credentials: MapSet.new()

  @privilege_order %{none: 0, user: 1, administrator: 2}

  def new(initial_foothold_id, privilege \\ :user) do
    %__MODULE__{
      footholds: MapSet.new([initial_foothold_id]),
      privileges: %{initial_foothold_id => privilege},
      credentials: MapSet.new()
    }
  end

  def foothold_nodes(state), do: MapSet.to_list(state.footholds)

  def add_foothold(state, host_id) do
    add_foothold(state, host_id, :user)
  end

  def add_foothold(state, host_id, privilege) do
    current_privilege = Map.get(state.privileges, host_id, :none)

    if privilege_order(privilege) > privilege_order(current_privilege) do
      %{
        state
        | footholds: MapSet.put(state.footholds, host_id),
          privileges: Map.put(state.privileges, host_id, privilege)
      }
    else
      %{state | footholds: MapSet.put(state.footholds, host_id)}
    end
  end

  def privilege_for(state, host_id) do
    Map.get(state.privileges, host_id, :none)
  end

  def has_privilege?(state, host_id, required) do
    current = privilege_for(state, host_id)
    privilege_order(current) >= privilege_order(required)
  end

  def add_credential(state, credential_id) do
    %{state | credentials: MapSet.put(state.credentials, credential_id)}
  end

  def has_credential?(state, credential_id) do
    MapSet.member?(state.credentials, credential_id)
  end

  def attempted?(state, action_key), do: MapSet.member?(state.attempted_actions, action_key)

  def mark_attempted(state, action_key) do
    %{state | attempted_actions: MapSet.put(state.attempted_actions, action_key)}
  end

  def to_map(%__MODULE__{} = state) do
    %{
      "footholds" => MapSet.to_list(state.footholds),
      "privileges" =>
        Map.new(state.privileges, fn {host_id, privilege} ->
          {host_id, Atom.to_string(privilege)}
        end),
      "credentials" => MapSet.to_list(state.credentials),
      "attempted_actions" =>
        state.attempted_actions
        |> Enum.map(&encode_action_key/1)
    }
  end

  def from_map(%{"footholds" => footholds, "attempted_actions" => attempted_actions} = map)
      when is_list(footholds) and is_list(attempted_actions) do
    with {:ok, attempted_actions} <- decode_action_keys(attempted_actions) do
      {:ok,
       %__MODULE__{
         footholds: MapSet.new(footholds),
         attempted_actions: MapSet.new(attempted_actions),
         privileges: privileges_from(map, footholds),
         credentials: credentials_from(map)
       }}
    end
  end

  def from_map(_), do: :error

  defp privilege_order(privilege) when is_atom(privilege),
    do: Map.get(@privilege_order, privilege, 0)

  defp privilege_order(privilege) when is_binary(privilege),
    do: privilege |> normalize_privilege() |> privilege_order()

  defp normalize_privilege(privilege) when privilege in [:none, :user, :administrator],
    do: privilege

  defp normalize_privilege("none"), do: :none
  defp normalize_privilege("user"), do: :user
  defp normalize_privilege("administrator"), do: :administrator
  defp normalize_privilege(_), do: :none

  defp privileges_from(%{"privileges" => privileges}, _footholds) when is_map(privileges) do
    Map.new(privileges, fn {host_id, privilege} -> {host_id, normalize_privilege(privilege)} end)
  end

  defp privileges_from(_map, footholds), do: Map.new(footholds, &{&1, :user})

  defp credentials_from(%{"credentials" => credentials}) when is_list(credentials),
    do: MapSet.new(credentials)

  defp credentials_from(_map), do: MapSet.new()

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
