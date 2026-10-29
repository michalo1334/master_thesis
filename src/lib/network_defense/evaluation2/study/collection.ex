defmodule NetworkDefense.Evaluation2.Study.Collection do
  @moduledoc false

  # Collection work of the Pilot and Final phases.
  #
  # One collection capability owns request planning, replica preparation, the two
  # mapped effects, and evidence assembly. Stored rows and transactions belong to
  # `NetworkDefense.Evaluation2.Study.Persistence`; the optimization and
  # simulation domains own the effects themselves.
  #
  # Mapped Gust tasks call the two effect functions. Gust owns batch execution,
  # dependency fan-in, and retry, so this module holds no scheduler, batch runner,
  # or retry loop.

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Tier

  # Construct or load the Pilot plan of one collection phase run.
  #
  # The plan covers the declared Pilot collection capacity, and a repeated call
  # returns the stored plan.
  @spec prepare_pilot(Ecto.UUID.t(), Definition.t()) ::
          {:ok, CollectionPlan.t()} | {:error, Error.t()}
  def prepare_pilot(_phase_run_id, _definition),
    do: {:error, Placeholder.error(:prepare_pilot)}

  # Construct or load the Final plan of one tier collection phase run.
  #
  # Every replica of the tier reuses this plan, and the two sample counts come
  # from the frozen selection.
  @spec prepare_final(Ecto.UUID.t(), Definition.t(), Selection.t(), Tier.t()) ::
          {:ok, CollectionPlan.t()} | {:error, Error.t()}
  def prepare_final(_phase_run_id, _definition, _selection, _tier),
    do: {:error, Placeholder.error(:prepare_final)}

  # Create or load the complete ordered item batch of one replica.
  #
  # Pilot uses measured replica 0. Final uses warm-up -1 and measured replicas
  # 0..4. One row exists per plan item, so a replica is always complete.
  @spec prepare_replica(Ecto.UUID.t(), CollectionItem.replica_position()) ::
          {:ok, [CollectionItem.t()]} | {:error, Error.t()}
  def prepare_replica(_plan_id, _replica_position),
    do: {:error, Placeholder.error(:prepare_replica)}

  # Reserve or reuse, run, and await the optimization effect of one item.
  #
  # Success returns `:ok` because the collection item already owns the effect
  # links.
  @spec run_optimization(Ecto.UUID.t()) :: :ok | {:error, Error.t()}
  def run_optimization(_item_id), do: {:error, Placeholder.error(:run_optimization)}

  # Reserve or reuse, run, and await the simulation effect of one item.
  #
  # The item links the completed optimization run that the simulation consumes.
  @spec run_simulation(Ecto.UUID.t()) :: :ok | {:error, Error.t()}
  def run_simulation(_item_id), do: {:error, Placeholder.error(:run_simulation)}

  # Assemble or load the evidence snapshot of one collection phase.
  #
  # The phase states the Pilot or Final role and owns the phase runs. Assembly
  # reads the accepted replica, builds one shared attack-column list per
  # comparison, and creates the snapshot once.
  @spec assemble_evidence(Ecto.UUID.t()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, Error.t()}
  def assemble_evidence(_study_phase_id),
    do: {:error, Placeholder.error(:assemble_evidence)}
end
