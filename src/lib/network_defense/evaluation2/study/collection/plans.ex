defmodule NetworkDefense.Evaluation2.Study.Collection.Plans do
  @moduledoc false

  # Authoritative work plans of the collection phase runs.
  #
  # One immutable plan belongs to one collection phase run. Preparation is one
  # idempotent operation: it constructs the resolved request list and persists it
  # for the phase run, and a repeated call returns the stored plan.
  #
  # The planner is the single owner of request construction. A lower-level
  # item-construction function stays private, so no caller holds an unowned plan
  # value.

  alias NetworkDefense.Evaluation2.CollectionPlan
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Tier

  # Construct or load the Pilot plan of one collection phase run.
  #
  # The plan covers the declared Pilot collection capacity.
  @spec prepare_pilot(Ecto.UUID.t(), Definition.t()) ::
          {:ok, CollectionPlan.t()} | {:error, Error.t()}
  def prepare_pilot(_phase_run_id, _definition),
    do: {:error, Placeholder.error(:prepare_pilot)}

  # Construct or load the Final plan of one tier collection phase run.
  #
  # Every replica of the tier reuses this plan. The two sample counts come from
  # the frozen selection.
  @spec prepare_final(Ecto.UUID.t(), Definition.t(), Selection.t(), Tier.t()) ::
          {:ok, CollectionPlan.t()} | {:error, Error.t()}
  def prepare_final(_phase_run_id, _definition, _selection, _tier),
    do: {:error, Placeholder.error(:prepare_final)}

  @spec fetch_for_run!(Ecto.UUID.t()) :: CollectionPlan.t()
  def fetch_for_run!(_phase_run_id),
    do: raise(NotImplementedError, function: :fetch_for_run!)
end
