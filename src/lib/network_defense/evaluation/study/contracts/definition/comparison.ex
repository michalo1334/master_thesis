defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Comparison do
  @moduledoc false

  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  use NetworkDefense.Contracts, export: false

  # One primary comparison inside the declared family.
  #
  # The five fields form the identity. The tier names a declared graph, the
  # alternative and the reference name strategies declared for that tier, and
  # the budget must agree with both declarations. The consistency check proves
  # those links after the shape is valid.

  @type t :: %__MODULE__{
          tier: String.t(),
          budget: pos_integer(),
          alternative: OptimizationParams.strategy(),
          reference: OptimizationParams.strategy(),
          outcome: String.t()
        }

  @typedoc "Canonical identity key. Two comparisons are equal when their keys are equal."
  @type key ::
          {String.t(), pos_integer(), OptimizationParams.strategy(),
           OptimizationParams.strategy(), String.t()}

  embedded_schema do
    field :tier, :string
    field :budget, :integer
    field :alternative, Ecto.Enum, values: OptimizationParams.strategy_values()
    field :reference, Ecto.Enum, values: OptimizationParams.strategy_values()
    field :outcome, :string
  end

  def changeset(comparison, attrs) do
    comparison
    |> cast(attrs, [:tier, :budget, :alternative, :reference, :outcome])
    |> validate_required([:tier, :budget, :alternative, :reference, :outcome])
    |> validate_number(:budget, greater_than: 0)
  end

  @spec key(t()) :: key()
  def key(%__MODULE__{} = comparison) do
    {
      comparison.tier,
      comparison.budget,
      comparison.alternative,
      comparison.reference,
      comparison.outcome
    }
  end
end
