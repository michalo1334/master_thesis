defmodule NetworkDefense.Evaluation2.StudyRevision do
  @moduledoc """
  Frozen study definition.

  One revision holds the parsed and normalized definition that creation already
  accepted. Every execution of that revision reads this record, so a later
  setting change creates a new revision instead of editing this one.
  """

  alias NetworkDefense.Evaluation2.Study.Definition

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          definition: Definition.t()
        }

  defstruct [:id, :definition]
end
