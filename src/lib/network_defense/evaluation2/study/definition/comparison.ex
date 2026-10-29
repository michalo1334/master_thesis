defmodule NetworkDefense.Evaluation2.Study.Definition.Comparison do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  @type t :: %__MODULE__{
          tier: String.t(),
          budget: pos_integer(),
          alternative: OptimizationParams.strategy(),
          reference: OptimizationParams.strategy(),
          outcome: String.t()
        }
  defstruct [:tier, :budget, :alternative, :reference, :outcome]
end
