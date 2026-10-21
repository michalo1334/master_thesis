defmodule NetworkDefense.Evaluation.Final.Contracts.Analysis do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  # Explicit Final analysis settings.
  #
  # No default exists. The values feed the accepted Stage 2 comparison
  # contract unchanged: the same corrected crossed bootstrap, the same centered
  # crossed-bootstrap test, and the same two-sided alternative.

  @type t :: %__MODULE__{
          alpha: float(),
          confidence_level: float(),
          test_alternative: String.t(),
          bootstrap_replicates: pos_integer()
        }

  embedded_schema do
    field :alpha, :float
    field :confidence_level, :float
    field :test_alternative, :string
    field :bootstrap_replicates, :integer
  end

  def changeset(analysis, attrs) do
    cast(analysis, attrs, [:alpha, :confidence_level, :test_alternative, :bootstrap_replicates])
  end
end
