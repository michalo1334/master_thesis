defmodule NetworkDefense.Evaluation.Study.Coordinator do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.{EvidenceSnapshots, Final, Pilot}

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request, Result}
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotResult}
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotRequest, as: PilotRequestContract

  alias NetworkDefense.Evaluation.Pilot.Work

  alias NetworkDefense.Evaluation.Study.{
    Collection,
    CollectionWorkflow,
    FinalReplicaSummaryAssembler,
    FinalRequest,
    FinalSnapshot,
    FinalTierWorkflow,
    Lifecycle,
    PhaseRuns,
    PilotOutcome,
    PilotRequest,
    Results,
    Revisions
  }

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.Timing.Canonical.MeasuredReplica

  alias NetworkDefense.Evaluation.Study.Timing.{
    Canonical,
    FinalReplicaSummary,
    ReplicaTiming
  }

  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyPhaseRun}
  alias NetworkDefense.Repo

  @terminal_states [:awaiting_final, :succeeded, :failed, :cancelled]
  @coordinator_registry NetworkDefense.Evaluation.Study.CoordinatorRegistry
  @failure_persistence_event [
    :network_defense,
    :evaluation,
    :study,
    :coordinator,
    :failure_persistence
  ]
  @start_timeout 5_000

  @spec start(Ecto.UUID.t()) :: {:ok, pid()} | {:error, StudyError.t()}
  def start(execution_id) do
    case Ecto.UUID.cast(execution_id) do
      {:ok, id} -> start_coordinator(id)
      :error -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp start_coordinator(execution_id) do
    caller = self()
    handshake = make_ref()

    case Task.Supervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
           claim_and_run(caller, handshake, execution_id, [])
         end) do
      {:ok, pid} -> await_start(pid, handshake)
      {:error, _reason} -> {:error, StudyError.coordinator_not_startable()}
    end
  end

  defp claim_and_run(caller, handshake, execution_id, opts) do
    case Registry.register(@coordinator_registry, execution_id, nil) do
      {:ok, _owner} ->
        case start_context(execution_id) do
          {:ok, _execution, _phase} ->
            send(caller, {:coordinator_claimed, handshake, self()})

            receive do
              {:run_coordinator, ^handshake} -> run(execution_id, opts)
            after
              @start_timeout -> :ok
            end

          {:stop, _state} ->
            send(caller, {:coordinator_start_error, handshake, self(), start_error()})

          {:error, %StudyError{} = error} ->
            send(caller, {:coordinator_start_error, handshake, self(), error})
        end

      {:error, {:already_registered, _pid}} ->
        send(caller, {:coordinator_start_error, handshake, self(), start_error()})
    end
  end

  defp await_start(pid, handshake) do
    monitor = Process.monitor(pid)

    receive do
      {:coordinator_claimed, ^handshake, ^pid} ->
        Process.demonitor(monitor, [:flush])
        send(pid, {:run_coordinator, handshake})
        {:ok, pid}

      {:coordinator_start_error, ^handshake, ^pid, %StudyError{} = error} ->
        Process.demonitor(monitor, [:flush])
        {:error, error}

      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        {:error, start_error()}
    after
      @start_timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
        {:error, start_error()}
    end
  end

  defp start_error, do: StudyError.coordinator_not_startable()

  @spec run(Ecto.UUID.t(), keyword()) :: :ok | {:error, StudyError.t()}
  def run(execution_id, opts \\ []) do
    case current_state(execution_id) do
      {:ok, :collecting_pilot} -> run_pilot(execution_id, opts)
      {:ok, :collecting_final} -> run_final(execution_id, opts)
      {:ok, state} when state in @terminal_states -> :ok
      _invalid -> {:error, StudyError.study_execution_not_found()}
    end
  rescue
    _exception ->
      error = unexpected_error(execution_id)
      fail_active(execution_id, error)
      {:error, error}
  end

  defp run_pilot(execution_id, opts) do
    collection = Keyword.get(opts, :collection_workflow, CollectionWorkflow)
    pilot = Keyword.get(opts, :pilot_workflow, Pilot.Workflow)

    result =
      with {:ok, _execution, collection_phase} <- context(execution_id, :collecting_pilot),
           {:ok, collection_run_id} <- collection.create(collection_phase),
           :ok <- accept_run(execution_id, :collecting_pilot, collection_phase, collection_run_id),
           :ok <-
             dispatch_run(
               execution_id,
               :collecting_pilot,
               collection_phase,
               collection_run_id,
               collection
             ),
           {:ok, snapshot_id} <- collection.await(collection_run_id),
           {:ok, execution, analysis_phase, definition} <-
             begin_analysis(execution_id, snapshot_id),
           {:ok, request} <- PilotRequest.build(execution, definition, snapshot_id),
           :ok <- validate_pilot_request(request),
           {:ok, analysis_run_id} <- pilot.create(Pilot.Wire.request(request)),
           :ok <- accept_run(execution_id, :analyzing_pilot, analysis_phase, analysis_run_id),
           :ok <-
             dispatch_run(
               execution_id,
               :analyzing_pilot,
               analysis_phase,
               analysis_run_id,
               pilot
             ),
           {:ok, :succeeded} <- pilot.await(analysis_run_id),
           {:ok, %PilotResult{} = pilot_result} <- pilot.result(analysis_run_id),
           {:ok, outcome} <- PilotOutcome.from_result(pilot_result) do
        finish_pilot(execution_id, outcome)
      end

    finish_run(execution_id, result, &bounded_pilot_error/1)
  end

  defp run_final(execution_id, opts) do
    tier_workflow = Keyword.get(opts, :final_tier_workflow, FinalTierWorkflow)
    final = Keyword.get(opts, :final_workflow, Final.Workflow)
    snapshot = Keyword.get(opts, :final_snapshot, FinalSnapshot)
    tier_timeout = Keyword.get(opts, :final_tier_timeout, :infinity)

    result =
      with {:ok, execution, collection_phase} <- context(execution_id, :collecting_final),
           {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
           {:ok, tiers} <- Collection.tier_order(definition),
           {:ok, _timings} <-
             run_tiers(execution_id, tiers, tier_workflow, tier_timeout),
           :ok <- require_collecting_final(execution_id),
           {:ok, items} <- assemble_replicas(collection_phase, definition),
           {:ok, snapshot_id} <- snapshot.assemble_and_store(collection_phase, items, definition),
           {:ok, execution, analysis_phase} <-
             begin_final_analysis(execution_id, snapshot_id, tiers),
           {:ok, %Request{} = request} <- FinalRequest.build(execution.id, snapshot_id),
           {:ok, analysis_run_id} <- final.create(Final.Wire.request(request)),
           :ok <- accept_run(execution_id, :analyzing_final, analysis_phase, analysis_run_id),
           :ok <-
             dispatch_run(
               execution_id,
               :analyzing_final,
               analysis_phase,
               analysis_run_id,
               final
             ),
           {:ok, :succeeded} <- final.await(analysis_run_id),
           {:ok, %Result{} = final_result} <- final.result(analysis_run_id),
           {:ok, _compact_result} <- Results.create_success(execution, final_result) do
        :ok
      end

    finish_run(execution_id, result, &bounded_final_error/1)
  end

  # Final collection runs one tier Gust run at a time, in first-seen comparison
  # order. The coordinator keeps the five measured timing values of each tier in
  # memory only. A tier starts only after the previous tier returned them.
  defp run_tiers(execution_id, tiers, workflow, timeout) do
    result =
      tiers
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, %{}}, fn {tier, tier_position}, {:ok, collected} ->
        case run_tier(execution_id, tier, tier_position, workflow, timeout) do
          {:ok, timings} ->
            {:cont,
             {:ok, Map.put(collected, tier, %{tier_position: tier_position, timings: timings})}}

          other ->
            {:halt, other}
        end
      end)

    with {:ok, collected} <- result,
         :ok <- validate_timing_family(collected, tiers) do
      {:ok, collected}
    end
  end

  defp run_tier(execution_id, tier, tier_position, workflow, timeout) do
    with {:ok, phase, phase_run} <- prepare_tier(execution_id, tier, tier_position),
         {:ok, gust_run_id} <- tier_run_id(workflow, phase_run),
         {:ok, _linked} <- link_tier_run(execution_id, phase, phase_run, gust_run_id),
         :ok <- dispatch_tier_run(execution_id, phase_run, gust_run_id, workflow),
         {:ok, timings} <-
           await_tier(workflow, execution_id, phase_run.id, gust_run_id, timeout),
         :ok <- validate_tier_timings(tier, timings) do
      {:ok, timings}
    end
  end

  # A phase-run row is created under the execution lock, so two coordinators
  # cannot create two rows for one tier position.
  defp prepare_tier(execution_id, tier, tier_position) do
    transaction(&locked_prepare_tier(&1, tier, tier_position), execution_id)
  end

  defp locked_prepare_tier(
         %StudyExecution{state: :collecting_final} = execution,
         tier,
         tier_position
       ) do
    phase = lock_named_phase(execution.id, :final_collection)

    case PhaseRuns.get_or_create(phase, tier, tier_position) do
      {:ok, %StudyPhaseRun{tier: ^tier, tier_position: ^tier_position} = phase_run} ->
        {:ok, phase, phase_run}

      {:ok, %StudyPhaseRun{}} ->
        Repo.rollback({:error, StudyError.phase_run_conflict()})

      {:error, %StudyError{} = error} ->
        Repo.rollback({:error, error})
    end
  end

  defp locked_prepare_tier(%StudyExecution{state: state}, _tier, _tier_position), do: stop(state)

  # One phase-run row owns one Gust run. A row that already links a run keeps it,
  # so a repeated coordination attempt never creates a second run for it.
  defp tier_run_id(workflow, %StudyPhaseRun{gust_run_id: nil} = phase_run),
    do: create_tier_run(workflow, phase_run)

  defp tier_run_id(_workflow, %StudyPhaseRun{gust_run_id: run_id})
       when is_integer(run_id) and run_id > 0,
       do: {:ok, run_id}

  defp create_tier_run(workflow, %StudyPhaseRun{} = phase_run) do
    case workflow.create(phase_run) do
      {:ok, run_id} when is_integer(run_id) and run_id > 0 -> {:ok, run_id}
      {:error, %StudyError{} = error} -> {:error, error}
      _invalid -> {:error, StudyError.final_collection_workflow_failed()}
    end
  end

  defp link_tier_run(execution_id, %StudyPhase{id: phase_id}, %StudyPhaseRun{id: id}, gust_run_id) do
    transaction(
      &locked_link_tier_run(&1, phase_id, id, gust_run_id),
      execution_id
    )
  end

  defp locked_link_tier_run(
         %StudyExecution{state: :collecting_final},
         phase_id,
         id,
         gust_run_id
       ) do
    case lock_phase_run(id) do
      %StudyPhaseRun{study_phase_id: ^phase_id, gust_run_id: nil} = phase_run ->
        link_locked_run(phase_run, gust_run_id)

      %StudyPhaseRun{study_phase_id: ^phase_id, gust_run_id: ^gust_run_id} = phase_run ->
        link_locked_run(phase_run, gust_run_id)

      %StudyPhaseRun{} ->
        Repo.rollback({:error, StudyError.phase_run_conflict()})
    end
  end

  defp locked_link_tier_run(%StudyExecution{state: state}, _phase_id, _id, _gust_run_id),
    do: stop(state)

  defp link_locked_run(%StudyPhaseRun{} = phase_run, gust_run_id) do
    case PhaseRuns.link_gust_run(phase_run, gust_run_id) do
      {:ok, %StudyPhaseRun{} = updated} -> {:ok, updated}
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
    end
  end

  defp dispatch_tier_run(execution_id, %StudyPhaseRun{id: id}, gust_run_id, workflow) do
    transaction(
      &locked_dispatch_tier_run(&1, id, gust_run_id, workflow),
      execution_id
    )
  end

  defp locked_dispatch_tier_run(
         %StudyExecution{state: :collecting_final},
         id,
         gust_run_id,
         workflow
       ) do
    case lock_phase_run(id) do
      %StudyPhaseRun{gust_run_id: ^gust_run_id} -> dispatch_locked_run(gust_run_id, workflow)
      %StudyPhaseRun{} -> Repo.rollback({:error, StudyError.phase_run_conflict()})
    end
  end

  defp locked_dispatch_tier_run(%StudyExecution{state: state}, _id, _gust_run_id, _workflow),
    do: stop(state)

  defp dispatch_locked_run(gust_run_id, workflow) do
    case workflow.dispatch(gust_run_id) do
      :ok -> :ok
      {:error, %StudyError{} = error} -> Repo.rollback({:error, error})
      _invalid -> Repo.rollback({:error, StudyError.final_collection_workflow_failed()})
    end
  end

  # The await boundary stays outside the database locks, so a timing marker and
  # a cancellation wake-up can reach the coordinator process. The stored state is
  # authoritative after the wait.
  defp await_tier(workflow, execution_id, phase_run_id, gust_run_id, timeout) do
    with {:ok, execution} <- reload_execution(execution_id),
         {:ok, %StudyPhaseRun{gust_run_id: ^gust_run_id} = phase_run} <-
           reload_phase_run(phase_run_id),
         {:ok, timings} <- workflow.await(execution, phase_run, timeout),
         :ok <- require_collecting_final(execution_id) do
      {:ok, timings}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      {:stop, _state} = stop -> stop
      {:ok, %StudyPhaseRun{}} -> {:error, StudyError.phase_run_conflict()}
      _invalid -> {:error, StudyError.final_collection_workflow_failed()}
    end
  end

  defp reload_execution(execution_id) do
    with {:ok, id} <- Ecto.UUID.cast(execution_id),
         %StudyExecution{} = execution <- Repo.get(StudyExecution, id) do
      {:ok, execution}
    else
      _invalid -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp reload_phase_run(phase_run_id) do
    with {:ok, id} <- Ecto.UUID.cast(phase_run_id),
         %StudyPhaseRun{} = phase_run <- Repo.get(StudyPhaseRun, id) do
      {:ok, phase_run}
    else
      _invalid -> {:error, StudyError.phase_run_conflict()}
    end
  end

  defp lock_phase_run(phase_run_id) do
    Repo.one!(from run in StudyPhaseRun, where: run.id == ^phase_run_id, lock: "FOR UPDATE")
  end

  defp require_collecting_final(execution_id) do
    transaction(
      fn execution ->
        if execution.state == :collecting_final, do: :ok, else: stop(execution.state)
      end,
      execution_id
    )
  end

  defp validate_tier_timings(tier, timings) when is_list(timings) do
    positions = Enum.map(timings, & &1.position)

    if Enum.all?(timings, &match?(%ReplicaTiming{tier: ^tier}, &1)) and
         positions == Enum.to_list(0..4) do
      :ok
    else
      {:error, StudyError.final_timing_incomplete()}
    end
  end

  defp validate_tier_timings(_tier, _timings),
    do: {:error, StudyError.final_timing_incomplete()}

  defp five_timings?([_, _, _, _, _]), do: true
  defp five_timings?(_timings), do: false

  defp validate_timing_family(collected, tiers) when is_map(collected) do
    valid? =
      Map.keys(collected) |> Enum.sort() == Enum.sort(tiers) and
        Enum.with_index(tiers)
        |> Enum.all?(fn {tier, position} ->
          case Map.fetch(collected, tier) do
            {:ok, %{tier_position: ^position, timings: timings}} ->
              five_timings?(timings)

            _missing ->
              false
          end
        end)

    if valid?, do: :ok, else: {:error, StudyError.final_timing_incomplete()}
  end

  # One complete-family summary per measured position, one canonical selector
  # call, and the accepted replica-zero summary.
  defp assemble_replicas(%StudyPhase{} = phase, %Definition{} = definition) do
    result =
      Enum.reduce_while(Enum.to_list(0..4), {:ok, %{}}, fn position, {:ok, collected} ->
        case assemble_replica(phase, definition, position) do
          {:ok, replica, items} ->
            {:cont, {:ok, Map.put(collected, position, {replica, items})}}

          {:error, %StudyError{} = error} ->
            {:halt, {:error, error}}
        end
      end)

    with {:ok, collected} <- result,
         {:ok, {zero_replica, zero_items}} <- fetch_replica(collected, 0),
         {:ok, %FinalReplicaSummary{} = selected} <- select_replica(collected),
         true <- selected == zero_replica.summary do
      {:ok, zero_items}
    else
      false -> {:error, StudyError.final_replica_mismatch()}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp assemble_replica(phase, %Definition{} = definition, position) do
    with {:ok, summary, items} <-
           FinalReplicaSummaryAssembler.assemble(phase, definition, position),
         {:ok, replica} <-
           Canonical.MeasuredReplica.validate(%MeasuredReplica{
             position: position,
             summary: summary
           }) do
      {:ok, replica, items}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      {:error, _reason} -> {:error, StudyError.final_replica_summary_invalid()}
    end
  end

  defp fetch_replica(collected, position) do
    case Map.fetch(collected, position) do
      {:ok, {_replica, _items} = entry} -> {:ok, entry}
      :error -> {:error, StudyError.incomplete_final_family()}
    end
  end

  defp select_replica(collected) do
    with {:ok, replicas} <- ordered_replicas(collected) do
      case Canonical.select(replicas) do
        {:ok, %FinalReplicaSummary{} = summary} -> {:ok, summary}
        {:error, :replica_mismatch} -> {:error, StudyError.final_replica_mismatch()}
        {:error, _reason} -> {:error, StudyError.final_replica_summary_invalid()}
      end
    end
  end

  defp ordered_replicas(collected) do
    result =
      Enum.reduce_while(Enum.to_list(0..4), {:ok, []}, fn position, {:ok, replicas} ->
        case fetch_replica(collected, position) do
          {:ok, {replica, _items}} -> {:cont, {:ok, [replica | replicas]}}
          {:error, %StudyError{} = error} -> {:halt, {:error, error}}
        end
      end)

    with {:ok, replicas} <- result, do: {:ok, Enum.reverse(replicas)}
  end

  defp finish_run(_execution_id, :ok, _mapper), do: :ok
  defp finish_run(_execution_id, {:stop, _state}, _mapper), do: :ok

  defp finish_run(execution_id, {:error, reason}, mapper) do
    error = mapper.(reason)
    fail_active(execution_id, error)
    {:error, error}
  end

  defp current_state(execution_id) do
    with {:ok, id} <- Ecto.UUID.cast(execution_id),
         %StudyExecution{} = execution <- Repo.get(StudyExecution, id) do
      {:ok, execution.state}
    else
      _invalid -> :error
    end
  end

  defp start_context(execution_id) do
    case current_state(execution_id) do
      {:ok, state} when state in [:collecting_pilot, :collecting_final] ->
        context(execution_id, state)

      {:ok, state} when state in @terminal_states ->
        {:stop, state}

      _invalid ->
        {:error, start_error()}
    end
  end

  defp context(execution_id, expected_state) do
    with {:ok, id} <- Ecto.UUID.cast(execution_id),
         %StudyExecution{} = execution <- Repo.get(StudyExecution, id),
         true <- execution.state == expected_state,
         %StudyPhase{} = phase <-
           Repo.get_by(StudyPhase, execution_id: id, phase: phase(expected_state)),
         :ok <- reject_legacy_final_run(expected_state, phase) do
      {:ok, execution, phase}
    else
      %StudyExecution{state: state} when state in @terminal_states -> {:stop, state}
      {:error, %StudyError{} = error} -> {:error, error}
      _invalid -> {:error, StudyError.study_execution_not_found()}
    end
  end

  # Final collection keeps one run per tier. A legacy scalar run on the
  # collection phase can never satisfy the tier family, so the run fails before
  # any timed tier work starts.
  defp reject_legacy_final_run(:collecting_final, %StudyPhase{gust_run_id: run_id})
       when not is_nil(run_id),
       do: {:error, StudyError.incomplete_final_family()}

  defp reject_legacy_final_run(_state, %StudyPhase{}), do: :ok

  defp accept_run(execution_id, expected_state, %StudyPhase{id: phase_id}, run_id) do
    transaction(
      &accept_locked_run(&1, expected_state, phase_id, run_id),
      execution_id
    )
  end

  defp accept_locked_run(
         %StudyExecution{state: state},
         expected_state,
         phase_id,
         run_id
       )
       when state == expected_state do
    phase = lock_phase(phase_id)

    case phase.gust_run_id do
      nil ->
        update_phase!(phase, %{gust_run_id: run_id})
        :ok

      ^run_id ->
        :ok

      _different_run_id ->
        Repo.rollback({:error, workflow_error(expected_state)})
    end
  end

  defp accept_locked_run(%StudyExecution{state: state}, _expected_state, _phase_id, _run_id) do
    stop(state)
  end

  defp dispatch_run(
         execution_id,
         expected_state,
         %StudyPhase{id: phase_id},
         run_id,
         workflow
       ) do
    transaction(
      &dispatch_locked_run(&1, expected_state, phase_id, run_id, workflow),
      execution_id
    )
  end

  defp dispatch_locked_run(
         %StudyExecution{state: state},
         expected_state,
         phase_id,
         run_id,
         workflow
       )
       when state == expected_state do
    phase = lock_phase(phase_id)
    dispatch_accepted_run(phase.gust_run_id, run_id, workflow, expected_state)
  end

  defp dispatch_locked_run(
         %StudyExecution{state: state},
         _expected_state,
         _phase_id,
         _run_id,
         _workflow
       ) do
    stop(state)
  end

  defp dispatch_accepted_run(accepted_run_id, run_id, workflow, expected_state)
       when accepted_run_id == run_id do
    case workflow.dispatch(run_id) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback({:error, reason})
      _invalid -> Repo.rollback({:error, workflow_error(expected_state)})
    end
  end

  defp dispatch_accepted_run(_accepted_run_id, _run_id, _workflow, expected_state) do
    Repo.rollback({:error, workflow_error(expected_state)})
  end

  defp validate_pilot_request(%PilotRequestContract{} = request) do
    with {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
         :ok <- PilotRequestContract.matches_snapshot(request, snapshot, payload) do
      Work.preflight(request, payload)
    end
  end

  defp begin_analysis(execution_id, snapshot_id) do
    case transaction(&begin_analysis_transition(&1, snapshot_id), execution_id) do
      %StudyExecution{} = execution -> load_analysis_context(execution)
      other -> other
    end
  end

  defp begin_analysis_transition(
         %StudyExecution{state: :collecting_pilot} = execution,
         snapshot_id
       ) do
    phase = lock_named_phase(execution.id, :pilot_collection)

    if is_nil(phase.snapshot_id) or phase.snapshot_id == snapshot_id do
      update_phase!(phase, %{snapshot_id: snapshot_id})
      transitioned = transition_execution!(execution, :pilot_collected)
      insert_pilot_analysis_phase!(execution.id)
      transitioned
    else
      Repo.rollback({:error, StudyError.collection_workflow_failed()})
    end
  end

  defp begin_analysis_transition(%StudyExecution{state: state}, _snapshot_id), do: stop(state)

  defp insert_pilot_analysis_phase!(execution_id) do
    %StudyPhase{}
    |> StudyPhase.changeset(%{execution_id: execution_id, phase: :pilot_analysis})
    |> Repo.insert()
    |> case do
      {:ok, %StudyPhase{}} -> :ok
      {:error, _changeset} -> Repo.rollback({:error, StudyError.pilot_analysis_failed()})
    end
  end

  defp load_analysis_context(%StudyExecution{} = execution) do
    with %StudyPhase{} = analysis_phase <-
           Repo.get_by(StudyPhase, execution_id: execution.id, phase: :pilot_analysis),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id) do
      {:ok, execution, analysis_phase, definition}
    else
      nil -> {:error, StudyError.invalid_study_phase()}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  defp begin_final_analysis(execution_id, snapshot_id, tiers) do
    case transaction(&begin_final_analysis_transition(&1, snapshot_id, tiers), execution_id) do
      %StudyExecution{} = execution ->
        case Repo.get_by(StudyPhase, execution_id: execution.id, phase: :final_analysis) do
          %StudyPhase{} = phase -> {:ok, execution, phase}
          nil -> {:error, StudyError.invalid_study_phase()}
        end

      other ->
        other
    end
  end

  defp begin_final_analysis_transition(
         %StudyExecution{state: :collecting_final} = execution,
         snapshot_id,
         tiers
       ) do
    phase = lock_named_phase(execution.id, :final_collection)
    :ok = require_ordered_family(phase, tiers)

    if is_nil(phase.snapshot_id) or phase.snapshot_id == snapshot_id do
      update_phase!(phase, %{snapshot_id: snapshot_id})
      transitioned = transition_execution!(execution, :final_collected)
      insert_final_analysis_phase!(execution.id)
      transitioned
    else
      Repo.rollback({:error, StudyError.final_collection_workflow_failed()})
    end
  end

  defp begin_final_analysis_transition(%StudyExecution{state: state}, _snapshot_id, _tiers),
    do: stop(state)

  # Final analysis starts only for a complete ordered tier-run family. The Final
  # collection phase keeps no scalar Gust run.
  defp require_ordered_family(%StudyPhase{id: phase_id} = phase, tiers) do
    case PhaseRuns.ordered_for_phase(phase_id) do
      {:ok, rows} ->
        complete? =
          is_nil(phase.gust_run_id) and
            Enum.map(rows, & &1.tier) == tiers and
            Enum.all?(rows, &(is_integer(&1.gust_run_id) and &1.gust_run_id > 0))

        if complete?, do: :ok, else: Repo.rollback({:error, StudyError.incomplete_final_family()})

      {:error, %StudyError{} = error} ->
        Repo.rollback({:error, error})
    end
  end

  defp insert_final_analysis_phase!(execution_id) do
    %StudyPhase{}
    |> StudyPhase.changeset(%{execution_id: execution_id, phase: :final_analysis})
    |> Repo.insert!()
  end

  defp finish_pilot(execution_id, %PilotOutcome{} = outcome) do
    params = PilotOutcome.to_params(outcome)

    transaction(
      fn execution ->
        if execution.state == :analyzing_pilot do
          phase = lock_named_phase(execution.id, :pilot_analysis)
          update_phase!(phase, %{result_ref: params})

          execution
          |> StudyExecution.changeset(%{pilot_outcome: params})
          |> Repo.update!()
          |> transition_execution!(:pilot_analyzed)

          :ok
        else
          stop(execution.state)
        end
      end,
      execution_id
    )
  end

  defp fail_active(execution_id, %StudyError{} = error) do
    params = StudyError.to_params(error)

    transaction(
      fn execution ->
        case execution.state do
          state
          when state in [
                 :collecting_pilot,
                 :analyzing_pilot,
                 :collecting_final,
                 :analyzing_final
               ] ->
            phase = lock_named_phase(execution.id, phase(state))
            update_phase!(phase, %{error: params})

            execution
            |> StudyExecution.changeset(%{error: params})
            |> Repo.update!()
            |> transition_execution!(:fail)

            :ok

          _cancelled_or_terminal ->
            :ok
        end
      end,
      execution_id
    )
  rescue
    _exception -> report_failure_persistence(execution_id, error)
  end

  defp report_failure_persistence(execution_id, error) do
    :telemetry.execute(
      @failure_persistence_event,
      %{},
      %{
        execution_id: execution_id,
        active_phase: active_phase(execution_id, error),
        failure: :persistence_failed
      }
    )
  end

  defp active_phase(execution_id, error) do
    case Repo.get(StudyExecution, execution_id) do
      %StudyExecution{state: state}
      when state in [:collecting_pilot, :analyzing_pilot, :collecting_final, :analyzing_final] ->
        phase(state)

      _inactive_or_unavailable ->
        error_phase(error)
    end
  rescue
    _exception -> error_phase(error)
  end

  defp error_phase(%StudyError{issues: issues}) do
    cond do
      Enum.any?(issues, &(Map.get(&1, "path") == ["pilot_collection"])) -> :pilot_collection
      Enum.any?(issues, &(Map.get(&1, "path") == ["pilot_analysis"])) -> :pilot_analysis
      Enum.any?(issues, &(Map.get(&1, "path") == ["final_collection"])) -> :final_collection
      Enum.any?(issues, &(Map.get(&1, "path") == ["final_analysis"])) -> :final_analysis
      true -> :unknown
    end
  end

  defp transaction(fun, execution_id) do
    result =
      Repo.transaction(fn ->
        case lock_execution(execution_id) do
          %StudyExecution{} = execution -> fun.(execution)
          nil -> Repo.rollback({:error, StudyError.study_execution_not_found()})
        end
      end)

    case result do
      {:ok, value} -> value
      {:error, value} -> value
    end
  end

  defp lock_execution(execution_id) do
    case Ecto.UUID.cast(execution_id) do
      {:ok, id} ->
        Repo.one(from execution in StudyExecution, where: execution.id == ^id, lock: "FOR UPDATE")

      :error ->
        nil
    end
  end

  defp lock_phase(phase_id) do
    Repo.one!(from phase in StudyPhase, where: phase.id == ^phase_id, lock: "FOR UPDATE")
  end

  defp lock_named_phase(execution_id, phase_name) do
    Repo.one!(
      from phase in StudyPhase,
        where: phase.execution_id == ^execution_id and phase.phase == ^phase_name,
        lock: "FOR UPDATE"
    )
  end

  defp update_phase!(phase, attrs), do: phase |> StudyPhase.changeset(attrs) |> Repo.update!()

  defp transition_execution!(%StudyExecution{} = execution, event) do
    {:ok, state} = Lifecycle.transition(execution.state, event)
    execution |> StudyExecution.changeset(%{state: state}) |> Repo.update!()
  end

  defp stop(state), do: Repo.rollback({:stop, state})

  defp phase(:collecting_pilot), do: :pilot_collection
  defp phase(:analyzing_pilot), do: :pilot_analysis
  defp phase(:collecting_final), do: :final_collection
  defp phase(:analyzing_final), do: :final_analysis

  defp unexpected_error(execution_id) do
    case Repo.get(StudyExecution, execution_id) do
      %StudyExecution{state: :collecting_pilot} -> StudyError.collection_workflow_failed()
      %StudyExecution{state: :analyzing_pilot} -> StudyError.pilot_analysis_failed()
      %StudyExecution{state: :collecting_final} -> StudyError.final_collection_workflow_failed()
      _analysis_or_unavailable -> StudyError.final_analysis_failed()
    end
  rescue
    _exception -> StudyError.final_analysis_failed()
  end

  defp workflow_error(:collecting_pilot), do: StudyError.collection_workflow_failed()
  defp workflow_error(:analyzing_pilot), do: StudyError.pilot_analysis_failed()
  defp workflow_error(:analyzing_final), do: StudyError.final_analysis_failed()

  defp bounded_pilot_error(%StudyError{} = error), do: error
  defp bounded_pilot_error(%PilotError{}), do: StudyError.pilot_analysis_failed()
  defp bounded_pilot_error(_reason), do: StudyError.pilot_analysis_failed()

  defp bounded_final_error(%StudyError{} = error), do: error
  defp bounded_final_error(%FinalError{}), do: StudyError.final_analysis_failed()
  defp bounded_final_error(_reason), do: StudyError.final_analysis_failed()
end
