defmodule NetworkDefense.Evaluation2.Study.Definition.Final do
  @moduledoc false

  use Spectral

  alias NetworkDefense.Evaluation2.Study.Definition.{FinalAnalysis, FinalCollection}

  @type t :: %__MODULE__{collection: FinalCollection.t(), analysis: FinalAnalysis.t()}
  defstruct [:collection, :analysis]
end
