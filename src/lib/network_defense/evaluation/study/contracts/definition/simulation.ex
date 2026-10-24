defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Simulation do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # The exact evidence-simulation settings that both phases execute.
  #
  # Evidence simulation measures one plan, so it holds no scoring controls. Its
  # trial count is not declared: the Pilot capacity and the resumed Final
  # candidate supply it.
  #
  # The rule list is explicit. A later phase must not fall back on the default
  # rule set, because the default is a runtime choice, not a study statement.

  @type t :: %__MODULE__{
          iterations_per_run: pos_integer(),
          max_attempts: pos_integer(),
          rules: [String.t()],
          require_pre_attack_feasibility: boolean()
        }

  @fields [
    :iterations_per_run,
    :max_attempts,
    :rules,
    :require_pre_attack_feasibility
  ]

  embedded_schema do
    field :iterations_per_run, :integer
    field :max_attempts, :integer
    field :rules, {:array, :string}
    field :require_pre_attack_feasibility, :boolean
  end

  def changeset(simulation, attrs) do
    simulation
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> validate_number(:iterations_per_run, greater_than: 0)
    |> validate_number(:max_attempts, greater_than: 0)
    |> validate_length(:rules, min: 1)
  end
end
