defmodule NetworkDefense.Evaluation2.Study.RevisionDetail do
  @moduledoc """
  Frozen detail of one study revision.

  `authored` holds only the declared scientific settings, in the values that a
  structured submission supplies. `context` holds the frozen provenance that
  the application captured at creation. `structure` holds the derived study
  structure. The value holds no source YAML, no persistence row and no
  execution history.
  """

  use Spectral

  alias NetworkDefense.Evaluation2.Study.AuthoredDefinition
  alias NetworkDefense.Evaluation2.Study.DefinitionStructure
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.RevisionContext

  @type t :: %__MODULE__{
          revision: Revision.t(),
          authored: AuthoredDefinition.t(),
          context: RevisionContext.t(),
          structure: DefinitionStructure.t()
        }

  defstruct [:revision, :authored, :context, :structure]
end
