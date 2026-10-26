defmodule NetworkDefense.Optimization.Contracts.SimulationSettings do
  @moduledoc false

  alias NetworkDefense.Optimization.SimulationObjective
  alias NetworkDefense.Rules.Registry, as: RulesRegistry

  use NetworkDefense.Contracts, category: :optimization

  @enum_values [
    objective: SimulationObjective.values(),
    rules: RulesRegistry.values()
  ]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :objective, Ecto.Enum, values: SimulationObjective.values()
    field :monte_carlo_trials, :integer
    field :iterations_per_run, :integer
    field :max_attempts, :integer, default: 1
    field :rules, {:array, Ecto.Enum}, values: RulesRegistry.values()
  end

  @type t :: %__MODULE__{
          objective: SimulationObjective.t(),
          monte_carlo_trials: pos_integer(),
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer(),
          rules: [RulesRegistry.rule_type()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :objective,
      :monte_carlo_trials,
      :iterations_per_run,
      :max_attempts,
      :rules
    ])
    |> validate_required([
      :objective,
      :monte_carlo_trials,
      :iterations_per_run,
      :max_attempts,
      :rules
    ])
    |> validate_number(:monte_carlo_trials, greater_than: 0)
    |> validate_number(:iterations_per_run, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_length(:rules, min: 1)
  end
end
