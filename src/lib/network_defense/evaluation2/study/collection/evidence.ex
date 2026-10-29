defmodule NetworkDefense.Evaluation2.Study.Collection.Evidence do
  @moduledoc """
  Evidence assembly of one collection phase.

  Assembly reads the immutable planned items and builds one aligned matrix pair
  per declared comparison. The declared family order fixes the comparison order,
  and one shared attack-column list fixes both sides, so a later analysis needs no
  realignment pass.

  The snapshot is created once per accepted phase. A retried assembly returns the
  same snapshot.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.CollectionItem
  alias NetworkDefense.Evaluation2.{Evidence, EvidenceSnapshot}
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Definition

  @doc """
  Build the evidence value of one phase from its completed items.

  The result follows the declared family order and holds one attack-column list
  per comparison.
  """
  @spec build(Definition.t(), Evidence.role(), [CollectionItem.t()]) :: Evidence.t()
  def build(_definition, _role, _items), do: raise(NotImplementedError, function: :build)

  @doc """
  Assemble and accept one evidence snapshot for an execution.

  Assembly runs after the mapped collection tasks of the phase succeeded.
  """
  @spec assemble(Ecto.UUID.t(), Evidence.role(), CollectionItem.replica_position()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, StudyError.t()}
  def assemble(_execution_id, _role, _replica_position),
    do: raise(NotImplementedError, function: :assemble)
end
