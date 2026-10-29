defmodule NetworkDefense.Evaluation2.StudyRevision do
  @moduledoc false

  # Frozen study definition.
  #
  # One revision holds the parsed and normalized definition that creation already
  # accepted. The revision stores its declared identity for the supported reads,
  # and it keeps an internal identifier for its foreign keys.
  #
  # A later setting change creates a new revision instead of editing this one.

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Revision

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_id: String.t(),
          revision: Revision.revision(),
          definition: Definition.t()
        }

  defstruct [:id, :study_id, :revision, :definition]
end
