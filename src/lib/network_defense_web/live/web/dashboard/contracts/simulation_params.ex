defmodule NetworkDefenseWeb.Web.Contracts.SimulationParams do
  @moduledoc false

  use NetworkDefenseWeb.Web.Contracts

  embedded_schema do
    field :monte_carlo_trials, :integer
    field :iterations_per_count, :integer
  end

  @type t :: %__MODULE__{
          monte_carlo_trials: integer(),
          iterations_per_count: integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:monte_carlo_trials, :iterations_per_count])
    |> validate_required([:monte_carlo_trials, :iterations_per_count])
    |> validate_number(:monte_carlo_trials, greater_than: 0)
    |> validate_number(:iterations_per_count, greater_than: 0)
  end
end
