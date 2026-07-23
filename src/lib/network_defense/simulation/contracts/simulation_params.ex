defmodule NetworkDefense.Simulation.Contracts.SimulationParams do
  @moduledoc false

  use NetworkDefense.Contracts, category: :simulation

  embedded_schema do
    field :monte_carlo_trials, :integer
    field :iterations_per_run, :integer
  end

  @type t :: %__MODULE__{
          monte_carlo_trials: integer(),
          iterations_per_run: integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:monte_carlo_trials, :iterations_per_run])
    |> validate_required([:monte_carlo_trials, :iterations_per_run])
    |> validate_number(:monte_carlo_trials, greater_than: 0)
    |> validate_number(:iterations_per_run, greater_than: 0)
  end
end
