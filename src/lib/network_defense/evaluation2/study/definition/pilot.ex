defmodule NetworkDefense.Evaluation2.Study.Definition.Pilot do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study.Definition.{Candidate, PilotAnalysis, PilotCollection}

  @type t :: %__MODULE__{
          candidates: [Candidate.t()],
          collection: PilotCollection.t(),
          analysis: PilotAnalysis.t()
        }
  defstruct [:candidates, :collection, :analysis]
end
