defmodule NetworkDefense.Evaluation2.Study.Final.CorrectedFamily do
  @moduledoc false

  # Corrected Final comparison results in declared family order.
  #
  # The Final analysis owns these comparison outputs. The envelope of the
  # reported family (identifier, method, alpha) stays in the immutable definition
  # and is joined when the supported result view is built.

  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily.Comparison

  @type t :: %__MODULE__{comparisons: [Comparison.t()]}

  defstruct [:comparisons]
end
