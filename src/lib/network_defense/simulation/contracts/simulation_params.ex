defmodule NetworkDefense.Simulation.Contracts.SimulationParams do
  @moduledoc false

  alias Ecto.Changeset
  use NetworkDefense.Contracts, category: :simulation

  embedded_schema do
    field :monte_carlo_trials, :integer
    field :iterations_per_run, :integer
    field :initial_foothold_node_id, :string
    field :seed, :integer
    field :generate_seed, :boolean, default: false
  end

  @type t :: %__MODULE__{
          monte_carlo_trials: integer(),
          iterations_per_run: integer(),
          initial_foothold_node_id: String.t(),
          seed: integer(),
          generate_seed: boolean()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(
      attrs,
      [
        :monte_carlo_trials,
        :iterations_per_run,
        :initial_foothold_node_id,
        :seed,
        :generate_seed
      ],
      default_values: [generate_seed: false]
    )
    |> validate_required([
      :monte_carlo_trials,
      :iterations_per_run,
      :initial_foothold_node_id,
      :generate_seed
    ])
    |> validate_number(:monte_carlo_trials, greater_than: 0)
    |> validate_number(:iterations_per_run, greater_than: 0)
    |> validate_seed_present_unless_generated()
  end

  defp validate_seed_present_unless_generated(changeset) do
    generate_seed = Changeset.get_field(changeset, :generate_seed)
    seed = Changeset.get_field(changeset, :seed)

    case {generate_seed, seed} do
      {false, nil} ->
        Changeset.add_error(changeset, :seed, "cannot be nil when :generate_seed is false")

      _ ->
        changeset
    end
  end
end
