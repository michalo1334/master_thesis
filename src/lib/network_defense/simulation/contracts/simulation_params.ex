defmodule NetworkDefense.Simulation.Contracts.SimulationParams do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Rules.Registry, as: RulesRegistry

  use NetworkDefense.Contracts, category: :simulation

  @enum_values [rules: RulesRegistry.values()]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :monte_carlo_trials, :integer
    field :iterations_per_run, :integer
    field :initial_foothold_node_id, :string
    field :seed, :integer
    field :generate_seed, :boolean, default: false
    field :max_attempts, :integer, default: 1
    field :rules, {:array, Ecto.Enum}, values: RulesRegistry.values()
    field :require_pre_attack_feasibility, :boolean
  end

  @type t :: %__MODULE__{
          monte_carlo_trials: integer(),
          iterations_per_run: integer(),
          initial_foothold_node_id: String.t(),
          seed: integer(),
          generate_seed: boolean(),
          max_attempts: pos_integer(),
          rules: [RulesRegistry.rule_type()],
          require_pre_attack_feasibility: boolean()
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
        :generate_seed,
        :max_attempts,
        :rules,
        :require_pre_attack_feasibility
      ],
      default_values: [generate_seed: false, max_attempts: 1]
    )
    |> validate_required([
      :monte_carlo_trials,
      :iterations_per_run,
      :initial_foothold_node_id,
      :generate_seed,
      :max_attempts,
      :rules,
      :require_pre_attack_feasibility
    ])
    |> validate_number(:monte_carlo_trials, greater_than: 0)
    |> validate_number(:iterations_per_run, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_number(:seed, greater_than_or_equal_to: 0)
    |> validate_length(:rules, min: 1)
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
