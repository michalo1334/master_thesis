defmodule NetworkDefense.Evaluation2.EvidenceSnapshot do
  @moduledoc """
  Accepted evidence matrices of one phase.

  Assembly creates the snapshot once from the planned collection items, and every
  later phase reads it by identifier. A retried assembly returns the same
  snapshot, so a phase never holds two evidence records for the same work.
  """

  alias NetworkDefense.Evaluation2.Evidence

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          execution_id: Ecto.UUID.t(),
          role: Evidence.role(),
          evidence: Evidence.t()
        }

  defstruct [:id, :execution_id, :role, :evidence]
end
