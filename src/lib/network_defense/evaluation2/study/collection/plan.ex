defmodule NetworkDefense.Evaluation2.Study.Collection.Plan do
  @moduledoc """
  Work planning of one collection phase.

  Planning converts the frozen definition and the applied selection into immutable
  work items with stable positions. Pilot planning covers the declared collection
  capacity. Final planning covers one declared tier at one replica position.

  Planning creates the declared family order and the planned sample dimensions, so
  later stages read them instead of rechecking them.
  """

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.WorkItem
  alias NetworkDefense.Evaluation2.CollectionItem
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Selection
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Tier

  @doc "Plan the Pilot collection work of one definition."
  @spec pilot(Definition.t()) :: [WorkItem.t()]
  def pilot(_definition), do: raise(NotImplementedError, function: :pilot)

  @doc """
  Plan the work of one Final tier replica.

  The tier is one network-size tier. Its position follows the closed
  `NetworkDefense.Evaluation2.Tier` order, so no position argument exists. The two
  sample counts come from the frozen selection, so every tier measures the same
  declared dimensions.
  """
  @spec final(
          Definition.t(),
          Selection.t(),
          Tier.t(),
          CollectionItem.replica_position()
        ) :: [WorkItem.t()]
  def final(_definition, _selection, _tier, _replica_position),
    do: raise(NotImplementedError, function: :final)
end
