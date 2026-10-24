defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.FinalAnalysis do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  # Final inference settings and the ordered comparison seeds.
  #
  # One seed belongs to each ordered comparison position, so the count follows
  # the declared family. The Final contract counts seeds only. It does not
  # forbid equal seed numbers, so this block does not forbid them either.
  #
  # The alpha must equal the declared family alpha, because one family carries
  # one correction level. The consistency check proves that agreement.

  @type t :: %__MODULE__{
          comparison_seeds: [non_neg_integer()],
          alpha: float(),
          confidence_level: float(),
          test_alternative: String.t(),
          bootstrap_replicates: pos_integer()
        }

  embedded_schema do
    field :comparison_seeds, {:array, :integer}
    field :alpha, :float
    field :confidence_level, :float
    field :test_alternative, :string
    field :bootstrap_replicates, :integer
  end

  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, [
      :comparison_seeds,
      :alpha,
      :confidence_level,
      :test_alternative,
      :bootstrap_replicates
    ])
    |> validate_required([
      :comparison_seeds,
      :alpha,
      :confidence_level,
      :test_alternative,
      :bootstrap_replicates
    ])
    |> validate_length(:comparison_seeds, min: 1)
    |> validate_number(:alpha, greater_than: 0, less_than: 1)
    |> validate_number(:confidence_level, greater_than: 0, less_than: 1)
    |> validate_number(:bootstrap_replicates, greater_than: 0)
  end
end
