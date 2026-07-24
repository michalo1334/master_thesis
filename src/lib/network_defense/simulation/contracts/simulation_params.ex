defmodule NetworkDefense.Simulation.Contracts.SimulationParams do
  @moduledoc false

  alias Ecto.Changeset
  use NetworkDefense.Contracts, category: :simulation

  embedded_schema do
    field :monte_carlo_trials, :integer
    field :iterations_per_run, :integer
    field :seed, :integer
    field :generate_seed, :boolean, default: false
  end

  @type t :: %__MODULE__{
          monte_carlo_trials: integer(),
          iterations_per_run: integer(),
          seed: integer(),
          generate_seed: boolean()
        }

  def changeset(schema, attrs) do
    changeset =
      schema
      |> cast(attrs, [:monte_carlo_trials, :iterations_per_run, :seed, :generate_seed],
        default_values: [generate_seed: false]
      )
      |> validate_required([:monte_carlo_trials, :iterations_per_run, :generate_seed])
      |> validate_number(:monte_carlo_trials, greater_than: 0)
      |> validate_number(:iterations_per_run, greater_than: 0)

    changeset
    |> validate_change(:seed, fn :seed, seed ->
      case {Changeset.get_field(changeset, :generate_seed), seed} do
        {false, nil} -> [seed: "cannot be nil when :generate_seed is false"]
        _ -> []
      end
    end)
  end
end
