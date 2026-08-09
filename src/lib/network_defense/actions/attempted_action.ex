defmodule NetworkDefense.Actions.AttemptedAction do
  @moduledoc """
  Represents one action variant and its attempt count.
  """
  use Ecto.Schema

  alias NetworkDefense.Actions.Registry

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
      action_type: Registry.type_for!(module),
      action_data: Ecto.embedded_dump(action, :json)
    }
  end

  @doc "Retrieves the action struct from the AttemptedAction."
  def action(%__MODULE__{action_type: type, action_data: data}) do
    case Registry.module_for(type) do
      nil -> raise ArgumentError, "unknown attempted action type"
      module -> Ecto.embedded_load(module, data, :json)
    end
  end

  @doc "Increments attempt count capped at max_attempts."
  def increment(%__MODULE__{attempt_count: count} = aa, max_attempts) do
    %{aa | attempt_count: min(count + 1, max_attempts)}
  end
end
