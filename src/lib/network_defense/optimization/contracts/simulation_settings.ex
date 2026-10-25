defmodule NetworkDefense.Optimization.Contracts.SimulationSettings do
  @moduledoc false

  use NetworkDefense.Contracts, category: :optimization

  embedded_schema do
    field :monte_carlo_trials, :integer
    field :iterations_per_run, :integer
    field :initial_foothold_node_id, :string
    field :max_attempts, :integer, default: 1
  end

  @type t :: %__MODULE__{
          monte_carlo_trials: integer(),
          iterations_per_run: integer(),
          initial_foothold_node_id: String.t(),
          max_attempts: pos_integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :monte_carlo_trials,
      :iterations_per_run,
      :initial_foothold_node_id,
      :max_attempts
    ])
    |> validate_required([
      :monte_carlo_trials,
      :iterations_per_run,
      :initial_foothold_node_id,
      :max_attempts
    ])
    |> validate_number(:monte_carlo_trials, greater_than: 0)
    |> validate_number(:iterations_per_run, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
  end
end
