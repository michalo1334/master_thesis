defmodule NetworkDefense.AttackerState.AttemptedAction do
  @moduledoc """
  Stores one action identity and its attempt count.
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

  def new(action_type, action_data) when is_binary(action_type) and is_map(action_data) do
    %__MODULE__{action_type: action_type, action_data: action_data}
  end

  def same_action?(left, right) do
    left.action_type == right.action_type and left.action_data == right.action_data
  end

  def increment(%__MODULE__{attempt_count: count} = attempted_action, max_attempts) do
    %{attempted_action | attempt_count: min(count + 1, max_attempts)}
  end
end
