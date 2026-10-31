defmodule NetworkDefense.Evaluation2.Study.Definition.Family do
  @moduledoc false

  use Spectral

  # Declared comparison family. The correction method and the comparison
  # membership are fixed facts of the construction, not operator settings.
  # Comparisons are derived in canonical order, so they are not stored here.

  @type t :: %__MODULE__{id: String.t(), alpha: float()}
  defstruct [:id, :alpha]
end
