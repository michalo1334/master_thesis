defmodule NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan do
  @moduledoc false

  # Immutable ordered work of one collection phase run.
  #
  # One plan belongs to one collection `StudyPhaseRun`. It holds the complete
  # resolved request list, so the warm-up and the measured replicas of a Final
  # tier share one plan. The item position inside the plan identifies the request
  # that one `CollectionItem` executes.
  #
  # Plan construction and persistence form one idempotent operation, so no caller
  # holds an unowned plan value.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Study.Collection.WorkItem

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          study_phase_run_id: Ecto.UUID.t(),
          items: [WorkItem.t()]
        }

  defstruct [:id, :study_phase_run_id, :items]

  @spec fetch_item!(t(), non_neg_integer()) :: WorkItem.t()
  def fetch_item!(_plan, _item_position),
    do: raise(NotImplementedError, function: :fetch_item!)
end
