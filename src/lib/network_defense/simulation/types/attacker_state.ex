defmodule NetworkDefense.Simulation.Types.AttackerState do
  @moduledoc false

  @behaviour Ecto.Type

  alias NetworkDefense.AttackerState.AttackerState

  def type, do: :map

  def embed_as(_format), do: :self
  def equal?(left, right), do: left == right

  def cast(%AttackerState{} = state), do: {:ok, state}
  def cast(value), do: load(value)

  def load(%{"footholds" => footholds, "privileges" => privileges, "credentials" => credentials})
      when is_list(footholds) and is_map(privileges) and is_list(credentials) do
    with {:ok, privileges} <- load_privileges(privileges) do
      {:ok,
       %AttackerState{
         footholds: MapSet.new(footholds),
         privileges: privileges,
         credentials: MapSet.new(credentials)
       }}
    end
  end

  def load(_), do: :error

  def dump(%AttackerState{} = state) do
    {:ok,
     %{
       "footholds" => MapSet.to_list(state.footholds),
       "privileges" => Map.new(state.privileges, &serialize_privilege/1),
       "credentials" => MapSet.to_list(state.credentials)
     }}
  end

  def dump(_), do: :error

  defp load_privileges(privileges) do
    Enum.reduce_while(privileges, {:ok, %{}}, fn
      {host_id, privilege}, {:ok, result} when is_binary(host_id) ->
        case deserialize_privilege(privilege) do
          {:ok, privilege} -> {:cont, {:ok, Map.put(result, host_id, privilege)}}
          :error -> {:halt, :error}
        end

      _, _ ->
        {:halt, :error}
    end)
  end

  defp serialize_privilege({host_id, privilege}), do: {host_id, Atom.to_string(privilege)}

  defp deserialize_privilege("none"), do: {:ok, :none}
  defp deserialize_privilege("user"), do: {:ok, :user}
  defp deserialize_privilege("administrator"), do: {:ok, :administrator}
  defp deserialize_privilege(_), do: :error
end
