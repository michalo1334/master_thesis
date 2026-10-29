defmodule NetworkDefense.Evaluation2.Study.Collection.Execute do
  @moduledoc """
  Execution of one planned collection item.

  Execution reserves the domain effects of the stored work item, runs the
  optimization and the simulation, and records the effect links on the item. A
  Gust retry of the same item reuses those links, so one item owns one
  optimization and one experiment.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.NotImplementedError

  @doc """
  Run one collection item.

  Success means the linked domain records completed. The item stores no result.
  """
  @spec run(Ecto.UUID.t()) :: {:ok, Ecto.UUID.t()} | {:error, StudyError.t()}
  def run(_collection_item_id), do: raise(NotImplementedError, function: :run)
end
