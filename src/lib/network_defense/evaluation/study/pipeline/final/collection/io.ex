defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{Phase, Planner}

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.{ReplicaTiming, TimingSummary}

  alias NetworkDefense.Evaluation.Study.{ExecutionAccess, Revisions}
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyPhase, StudyPhaseRun}
  alias NetworkDefense.Repo

  # In-process state of the Final collection stage.
  #
  # A Gust task persists compact identifiers only. Every task rebuilds this IO
  # from the stored Gust run, the stored phase run, and PostgreSQL rows, so a
  # large value never crosses a task boundary.
  #
  # The tier and replica values are scoped to the task that receives them: one
  # environment boundary and one completion read the tier, one mapped step reads
  # one item, and the phase value is the later handoff to Final analysis.
  @phase :final_collection
  @active_state :collecting_final

  @enforce_keys [:execution, :phase, :definition, :tiers]
  defstruct [
    :execution,
    :phase,
    :definition,
    :timing,
    :snapshot_id,
    tiers: [],
    runs: [],
    items: []
  ]

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          phase: StudyPhase.t(),
          definition: Definition.t(),
          tiers: [String.t()],
          runs: [Tier.t()],
          timing: TimingSummary.t() | nil,
          snapshot_id: Ecto.UUID.t() | nil,
          items: [Item.t()]
        }

  # One stored tier run with its Gust run identifier.
  defmodule Tier do
    @moduledoc false

    alias NetworkDefense.Evaluation.Study.Contracts.Definition
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.Timing.ReplicaTiming
    alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyPhaseRun}

    @enforce_keys [:execution, :phase, :definition, :tier, :tier_position, :phase_run]
    defstruct [
      :execution,
      :phase,
      :definition,
      :tier,
      :tier_position,
      :phase_run,
      :gust_run,
      timings: []
    ]

    @type t :: %__MODULE__{
            execution: StudyExecution.t(),
            phase: StudyPhase.t(),
            definition: Definition.t(),
            tier: String.t(),
            tier_position: non_neg_integer(),
            phase_run: StudyPhaseRun.t(),
            gust_run: Gust.Flows.Run.t() | nil,
            timings: [ReplicaTiming.t()]
          }
  end

  # One replica position of a tier run.
  defmodule Replica do
    @moduledoc false

    alias NetworkDefense.Evaluation.Study.Contracts.StudyError
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO.Tier

    @enforce_keys [:tier, :replica_position]
    defstruct [:tier, :replica_position, items: []]

    @type t :: %__MODULE__{
            tier: Tier.t(),
            replica_position: -1..4,
            items: [NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO.Item.t()]
          }

    @spec for_tier(Tier.t(), term()) :: {:ok, t()} | {:error, StudyError.t()}
    def for_tier(%Tier{} = tier, replica_position)
        when is_integer(replica_position) and replica_position in -1..4 do
      {:ok, %__MODULE__{tier: tier, replica_position: replica_position}}
    end

    def for_tier(%Tier{}, _replica_position),
      do: {:error, StudyError.invalid_collection_position(:replica_position)}
  end

  # One stable collection item, with the effect it produced when known.
  defmodule Item do
    @moduledoc false

    alias NetworkDefense.Evaluation.Study.Contracts.StudyError
    alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Receipt
    alias NetworkDefense.Evaluation.StudyCollectionItem
    alias NetworkDefense.Repo

    @enforce_keys [:collection_item_id]
    defstruct [:collection_item_id, :collection_item, :receipt]

    @type t :: %__MODULE__{
            collection_item_id: Ecto.UUID.t(),
            collection_item: StudyCollectionItem.t() | nil,
            receipt: Receipt.t() | nil
          }

    # One mapped task payload. The stable identifier is the whole item input.
    @spec load_from_args(keyword()) :: {:ok, t()} | {:error, StudyError.t()}
    def load_from_args(args) when is_list(args) do
      args |> Keyword.get(:collection_item_id) |> load()
    end

    @spec load(term()) :: {:ok, t()} | {:error, StudyError.t()}
    def load(collection_item_id) do
      with {:ok, id} <- cast(collection_item_id),
           %StudyCollectionItem{} = item <- Repo.get(StudyCollectionItem, id) do
        {:ok, %__MODULE__{collection_item_id: id, collection_item: item}}
      else
        _invalid -> {:error, StudyError.collection_item_not_found()}
      end
    end

    defp cast(value), do: Ecto.UUID.cast(value)
  end

  # One measured timing boundary. The coordinator receives the same tuple it
  # always received, and answers with the same acknowledgement.
  defmodule Marker do
    @moduledoc false

    @type event ::
            :plan_dispatch | :plan_completion | :simulation_dispatch | :simulation_completion

    @enforce_keys [:execution_id, :phase_run_id, :replica_position, :event_kind]
    defstruct [:execution_id, :phase_run_id, :replica_position, :event_kind]

    @type t :: %__MODULE__{
            execution_id: Ecto.UUID.t(),
            phase_run_id: Ecto.UUID.t(),
            replica_position: 0..4,
            event_kind: event()
          }
  end

  @spec load(term()) :: {:ok, t()} | {:error, StudyError.t()} | {:stop, atom()}
  def load(execution_id) do
    with {:ok, execution} <- ExecutionAccess.fetch(execution_id),
         :ok <- active?(execution),
         {:ok, phase} <- collection_phase(execution),
         :ok <- no_scalar_run(phase),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, tiers} <- ordered_tiers(definition) do
      {:ok, %__MODULE__{execution: execution, phase: phase, definition: definition, tiers: tiers}}
    end
  end

  # One stored tier run, read from its phase-run row.
  @spec load_tier(term()) :: {:ok, Tier.t()} | {:error, StudyError.t()}
  def load_tier(phase_run_id) do
    with {:ok, phase_run} <- stored_phase_run(phase_run_id) do
      tier_run(phase_run, nil)
    end
  end

  # One tier run, read from the Gust run that owns it.
  #
  # The run parameters are the task input, so every stored relation is checked
  # against them before a task trusts the loaded rows.
  @spec load_tier_from_gust_run(term()) :: {:ok, Tier.t()} | {:error, StudyError.t()}
  def load_tier_from_gust_run(run_id) do
    with {:ok, run} <- gust_run(run_id),
         {:ok, phase_run} <- stored_phase_run(Map.get(run.params, "study_phase_run_id")),
         {:ok, tier} <- tier_run(phase_run, run),
         :ok <- matching_identity(tier.phase, phase_run, run.params) do
      {:ok, tier}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      _invalid -> {:error, StudyError.invalid_study_phase()}
    end
  end

  # One timing marker. Only the identity of the boundary crosses Gust.
  @spec load_marker(term(), term(), term()) :: {:ok, Marker.t()} | {:error, StudyError.t()}
  def load_marker(run_id, replica_position, event_kind) do
    with {:ok, position} <- marker_position(replica_position),
         {:ok, event} <- marker_event(event_kind),
         {:ok, run} <- gust_run(run_id),
         {:ok, phase_run} <- timing_phase_run(Map.get(run.params, "study_phase_run_id")),
         {:ok, phase} <- timing_phase(phase_run.study_phase_id),
         :ok <- matching_identity(phase, phase_run, run.params) do
      {:ok,
       %Marker{
         execution_id: phase.execution_id,
         phase_run_id: phase_run.id,
         replica_position: position,
         event_kind: event
       }}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      _invalid -> {:error, StudyError.final_timing_invalid()}
    end
  end

  @events [:plan_dispatch, :plan_completion, :simulation_dispatch, :simulation_completion]

  defp tier_run(%StudyPhaseRun{} = phase_run, run) do
    with {:ok, phase} <- phase_row(phase_run.study_phase_id),
         {:ok, execution} <- ExecutionAccess.fetch_trusted(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         :ok <- declared_tier(definition, phase_run) do
      {:ok,
       %Tier{
         execution: execution,
         phase: phase,
         definition: definition,
         tier: phase_run.tier,
         tier_position: phase_run.tier_position,
         phase_run: phase_run,
         gust_run: run
       }}
    end
  end

  # A stored tier names the tier at its declared position, so a renamed or
  # reordered definition cannot be collected under an old row.
  defp declared_tier(definition, %StudyPhaseRun{tier: tier, tier_position: position})
       when is_integer(position) and position >= 0 do
    with {:ok, tiers} <- ordered_tiers(definition) do
      if Enum.at(tiers, position) == tier, do: :ok, else: :error
    end
  end

  defp declared_tier(_definition, _phase_run), do: :error

  defp ordered_tiers(definition) do
    case Planner.tier_order(definition) do
      {:ok, tiers} -> {:ok, tiers}
      _invalid -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp collection_phase(execution), do: Phase.fetch(execution, @phase)

  defp active?(execution), do: Phase.ensure_active(execution, @active_state)

  # Final collection keeps one run per tier. A legacy scalar run on the collection
  # phase can never satisfy the tier family, so the stage fails before any timed
  # tier work starts.
  defp no_scalar_run(%StudyPhase{gust_run_id: nil}), do: :ok

  defp no_scalar_run(%StudyPhase{}), do: {:error, StudyError.incomplete_final_family()}

  defp phase_row(id) do
    case Repo.get(StudyPhase, id) do
      %StudyPhase{phase: @phase} = phase -> {:ok, phase}
      %StudyPhase{} -> {:error, StudyError.invalid_study_phase()}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp timing_phase(id) do
    case Repo.get(StudyPhase, id) do
      %StudyPhase{phase: @phase} = phase -> {:ok, phase}
      %StudyPhase{} -> {:error, StudyError.final_timing_invalid()}
      nil -> {:error, StudyError.final_timing_unavailable()}
    end
  end

  defp stored_phase_run(id) do
    with {:ok, id} <- cast(id),
         %StudyPhaseRun{} = phase_run <- Repo.get(StudyPhaseRun, id) do
      {:ok, phase_run}
    else
      _invalid -> {:error, StudyError.phase_run_storage_failed()}
    end
  end

  defp timing_phase_run(id) do
    case stored_phase_run(id) do
      {:ok, phase_run} -> {:ok, phase_run}
      {:error, _error} -> {:error, StudyError.final_timing_unavailable()}
    end
  end

  defp gust_run(run_id) when is_integer(run_id) and run_id > 0 do
    {:ok, Gust.Flows.get_run!(run_id)}
  rescue
    _exception -> :error
  end

  defp gust_run(_run_id), do: :error

  # The parameters are the only task input, so they must agree with the rows.
  defp matching_identity(%StudyPhase{} = phase, %StudyPhaseRun{} = phase_run, params)
       when is_map(params) do
    identities = [
      {params["study_phase_run_id"], phase_run.id},
      {params["study_phase_id"], phase.id},
      {params["execution_id"], phase.execution_id},
      {params["tier"], phase_run.tier},
      {params["tier_position"], phase_run.tier_position}
    ]

    if Enum.all?(identities, fn {given, stored} -> given == stored end), do: :ok, else: :error
  end

  defp matching_identity(_phase, _phase_run, _params), do: :error

  defp marker_position(position) when is_integer(position) and position in 0..4,
    do: {:ok, position}

  defp marker_position(_position), do: {:error, StudyError.final_timing_invalid()}

  defp marker_event(event) when event in @events, do: {:ok, event}

  defp marker_event(event) when is_binary(event) do
    case Enum.find(@events, fn known -> Atom.to_string(known) == event end) do
      nil -> {:error, StudyError.final_timing_invalid()}
      known -> {:ok, known}
    end
  end

  defp marker_event(_event), do: {:error, StudyError.final_timing_invalid()}

  defp cast(value), do: Ecto.UUID.cast(value)
end
