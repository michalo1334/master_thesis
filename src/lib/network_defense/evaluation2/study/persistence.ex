defmodule NetworkDefense.Evaluation2.Study.Persistence do
  @moduledoc false

  # The one data-access boundary of the study subsystem.
  #
  # Every stored record of a study is read or written here: the frozen revision,
  # the execution lifecycle row, phase and phase-run links, collection plans and
  # items, accepted evidence snapshots, and the stored Final result.
  #
  # The boundary moves internal records only. Supported values are built by
  # `NetworkDefense.Evaluation2.Study.Views`, and the short application flow
  # belongs to `NetworkDefense.Evaluation2.Study`, so this module holds no view
  # construction and no scientific calculation.
  #
  # Composite operations are transactions: an approval, a cancellation, and an
  # effect reservation each lock their row and commit once, so a retry reuses the
  # stored record instead of creating a second one.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Collection.WorkItem
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Evidence
  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.Study.Persistence.Execution
  alias NetworkDefense.Evaluation2.Study.Persistence.Phase
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun
  alias NetworkDefense.Evaluation2.Study.Persistence.Result
  alias NetworkDefense.Evaluation2.Study.Persistence.Revision
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Simulation.Experiment

  # --- revisions -----------------------------------------------------------

  # Freeze one revision from YAML text.
  #
  # Creation is the one external check point: it parses the document, checks the
  # definition, and resolves the declared graph references before it stores the
  # normalized definition.
  @spec create_revision(binary()) :: {:ok, Revision.t()} | {:error, Error.t()}
  def create_revision(_document), do: {:error, Placeholder.error(:create_revision)}

  # Resolve one declared revision identity to its stored record.
  @spec fetch_revision(Study.Revision.t()) :: {:ok, Revision.t()} | {:error, Error.t()}
  def fetch_revision(_revision), do: {:error, Placeholder.error(:fetch_revision)}

  @spec fetch_revision!(Study.Revision.t()) :: Revision.t()
  def fetch_revision!(_revision), do: raise(NotImplementedError, function: :fetch_revision!)

  @spec load_definition!(Ecto.UUID.t()) :: Definition.t()
  def load_definition!(_revision_id), do: raise(NotImplementedError, function: :load_definition!)

  # --- executions ----------------------------------------------------------

  # Write one execution in the initial Pilot collection state.
  @spec start_execution(Revision.t()) :: {:ok, Execution.t()} | {:error, Error.t()}
  def start_execution(_revision), do: {:error, Placeholder.error(:start_execution)}

  # Load one execution together with the revision it runs.
  #
  # The two records are read in one query because every status view needs both.
  @spec fetch_execution(Ecto.UUID.t()) ::
          {:ok, {Execution.t(), Revision.t()}} | {:error, Error.t()}
  def fetch_execution(_execution_id), do: {:error, Placeholder.error(:fetch_execution)}

  @spec fetch_execution!(Ecto.UUID.t()) :: {Execution.t(), Revision.t()}
  def fetch_execution!(_execution_id), do: raise(NotImplementedError, function: :fetch_execution!)

  @spec put_pilot_outcome(Execution.t(), PilotOutcome.t()) :: {:ok, Execution.t()}
  def put_pilot_outcome(_execution, _outcome),
    do: raise(NotImplementedError, function: :put_pilot_outcome)

  @spec put_selection(Execution.t(), Selection.t()) :: {:ok, Execution.t()}
  def put_selection(_execution, _selection),
    do: raise(NotImplementedError, function: :put_selection)

  # Accept one approval intent and commit the frozen selection.
  #
  # The transaction locks the waiting row, checks the intent against the stored
  # Pilot outcome, resolves the declared candidate counts, and commits the
  # lifecycle resume event. Final collection starts after the commit.
  @spec accept_approval(Ecto.UUID.t(), Study.approval()) ::
          {:ok, {Execution.t(), Revision.t()}} | {:error, Error.t()}
  def accept_approval(_execution_id, _approval),
    do: {:error, Placeholder.error(:accept_approval)}

  # Cancel one execution that is not terminal.
  #
  # A terminal state keeps its stored status, so a late phase completion cannot
  # advance a cancelled execution.
  @spec cancel_execution(Ecto.UUID.t()) ::
          {:ok, {Execution.t(), Revision.t()}} | {:error, Error.t()}
  def cancel_execution(_execution_id), do: {:error, Placeholder.error(:cancel_execution)}

  # --- stored results ------------------------------------------------------

  # Store the Final-owned family and timing of one successful execution.
  @spec store_result(Execution.t(), CorrectedFamily.t(), Timing.t()) ::
          {:ok, Result.t()} | {:error, Error.t()}
  def store_result(_execution, _family, _timing),
    do: {:error, Placeholder.error(:store_result)}

  @spec fetch_result(Execution.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def fetch_result(_execution), do: {:error, Placeholder.error(:fetch_result)}

  @spec fetch_result!(Execution.t()) :: Result.t()
  def fetch_result!(_execution), do: raise(NotImplementedError, function: :fetch_result!)

  # --- phases --------------------------------------------------------------

  # Create or load the phase record of one execution.
  @spec create_or_load_phase(Execution.t(), Phase.phase_kind()) ::
          {:ok, Phase.t()} | {:error, Error.t()}
  def create_or_load_phase(_execution, _phase_kind),
    do: {:error, Placeholder.error(:create_or_load_phase)}

  @spec fetch_phase!(Ecto.UUID.t(), Phase.phase_kind()) :: Phase.t()
  def fetch_phase!(_execution_id, _phase_kind),
    do: raise(NotImplementedError, function: :fetch_phase!)

  # Create or load one Gust run link of a phase.
  #
  # Single-run phases use the `:single` key and Final collection uses one tier
  # key per declared tier.
  @spec create_or_load_phase_run(Phase.t(), PhaseRun.run_key()) ::
          {:ok, PhaseRun.t()} | {:error, Error.t()}
  def create_or_load_phase_run(_phase, _run_key),
    do: {:error, Placeholder.error(:create_or_load_phase_run)}

  @spec fetch_phase_run!(Ecto.UUID.t()) :: PhaseRun.t()
  def fetch_phase_run!(_phase_run_id), do: raise(NotImplementedError, function: :fetch_phase_run!)

  @spec list_phase_runs(Phase.t()) :: [PhaseRun.t()]
  def list_phase_runs(_phase), do: raise(NotImplementedError, function: :list_phase_runs)

  # --- collection plans and items ------------------------------------------

  # Persist the resolved request list of one collection phase run.
  @spec store_collection_plan(PhaseRun.t(), [WorkItem.t()]) ::
          {:ok, CollectionPlan.t()} | {:error, Error.t()}
  def store_collection_plan(_phase_run, _items),
    do: {:error, Placeholder.error(:store_collection_plan)}

  @spec fetch_collection_plan!(PhaseRun.t()) :: CollectionPlan.t()
  def fetch_collection_plan!(_phase_run),
    do: raise(NotImplementedError, function: :fetch_collection_plan!)

  # Create one item row per plan item for one replica position.
  @spec store_collection_items(CollectionPlan.t(), CollectionItem.replica_position()) ::
          {:ok, [CollectionItem.t()]} | {:error, Error.t()}
  def store_collection_items(_plan, _replica_position),
    do: {:error, Placeholder.error(:store_collection_items)}

  @spec fetch_collection_item!(Ecto.UUID.t()) :: CollectionItem.t()
  def fetch_collection_item!(_item_id),
    do: raise(NotImplementedError, function: :fetch_collection_item!)

  @spec list_replica_items(PhaseRun.t(), CollectionItem.replica_position()) ::
          [CollectionItem.t()]
  def list_replica_items(_phase_run, _replica_position),
    do: raise(NotImplementedError, function: :list_replica_items)

  # Reserve or reuse the optimization run of one collection item.
  #
  # The row lock and the create-or-reuse transaction make a retry return the
  # linked record instead of a second one.
  @spec reserve_optimization(CollectionItem.t()) ::
          {:ok, OptimizationRun.t()} | {:error, Error.t()}
  def reserve_optimization(_item), do: {:error, Placeholder.error(:reserve_optimization)}

  # The experiment consumes the optimization run already linked by the item, so
  # a retry of the simulation stage reuses one experiment.
  @spec reserve_experiment(CollectionItem.t()) ::
          {:ok, Experiment.t()} | {:error, Error.t()}
  def reserve_experiment(_item), do: {:error, Placeholder.error(:reserve_experiment)}

  # --- evidence snapshots --------------------------------------------------

  # Storage is keyed by the owning collection phase, so one snapshot exists per
  # phase no matter how often acceptance is retried.
  @spec store_evidence_snapshot(Phase.t(), Evidence.t()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, Error.t()}
  def store_evidence_snapshot(_phase, _evidence),
    do: {:error, Placeholder.error(:store_evidence_snapshot)}

  @spec fetch_evidence_snapshot!(Phase.t()) :: EvidenceSnapshot.t()
  def fetch_evidence_snapshot!(_phase),
    do: raise(NotImplementedError, function: :fetch_evidence_snapshot!)
end
