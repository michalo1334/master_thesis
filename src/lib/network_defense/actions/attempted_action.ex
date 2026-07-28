defmodule NetworkDefense.Actions.AttemptedAction do
  @moduledoc """
  Represents one action variant and its attempt count.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{
          attempt_count: non_neg_integer(),
          action_type: String.t(),
          action_data: map()
        }

  @primary_key false
  embedded_schema do
    field :attempt_count, :integer, default: 0
    field :action_type, :string
    field :action_data, :map
  end

  @doc "Constructs an AttemptedAction from an action struct."
  def new(%module{} = action) do
    %__MODULE__{
      attempt_count: 0,
      action_type: Atom.to_string(module),
      action_data: Ecto.embedded_dump(action, :json)
    }
  end

  @doc "Retrieves the action struct from the AttemptedAction."
  def action(%__MODULE__{action_type: type, action_data: data}) do
    module = action_module!(type)
    Ecto.embedded_load(module, data, :json)
  end

  @doc "Increments attempt count capped at max_attempts."
  def increment(%__MODULE__{attempt_count: count} = aa, max_attempts) do
    %{aa | attempt_count: min(count + 1, max_attempts)}
  end

  defp action_module!("Elixir.NetworkDefense.Actions.ExploitVulnerability"),
    do: NetworkDefense.Actions.ExploitVulnerability

  defp action_module!("Elixir.NetworkDefense.Actions.AcquireCredential"),
    do: NetworkDefense.Actions.AcquireCredential

  defp action_module!("Elixir.NetworkDefense.Actions.ReuseCredential"),
    do: NetworkDefense.Actions.ReuseCredential
end
