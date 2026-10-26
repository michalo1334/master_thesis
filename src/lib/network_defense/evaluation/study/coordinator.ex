defmodule NetworkDefense.Evaluation.Study.Coordinator do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.{EvidenceSnapshots, Final, Pilot}

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request, Result}
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotResult}
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotRequest, as: PilotRequestContract

  alias NetworkDefense.Evaluation.Pilot.Work

  alias NetworkDefense.Evaluation.Study.{
    CollectionWorkflow,
    FinalCollectionWorkflow,
    FinalRequest,
    Lifecycle,
    PilotOutcome,
    PilotRequest,
    Results,
    Revisions
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
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
    collection = Keyword.get(opts, :final_collection_workflow, FinalCollectionWorkflow)
    final = Keyword.get(opts, :final_workflow, Final.Workflow)

    result =
      with {:ok, _execution, collection_phase} <- context(execution_id, :collecting_final),
           {:ok, collection_run_id} <- collection.create(collection_phase),
           :ok <- accept_run(execution_id, :collecting_final, collection_phase, collection_run_id),
           :ok <-
             dispatch_run(
               execution_id,
               :collecting_final,
               collection_phase,
               collection_run_id,
               collection
             ),
           {:ok, snapshot_id} <- collection.await(collection_run_id),
           {:ok, execution, analysis_phase} <-
             begin_final_analysis(execution_id, snapshot_id),
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
           Repo.get_by(StudyPhase, execution_id: id, phase: phase(expected_state)) do
      {:ok, execution, phase}
    else
      %StudyExecution{state: state} when state in @terminal_states -> {:stop, state}
      _invalid -> {:error, StudyError.study_execution_not_found()}
    end
  end

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
    store_collected_snapshot(execution, phase, snapshot_id)
  end

  defp begin_analysis_transition(%StudyExecution{state: state}, _snapshot_id), do: stop(state)

  defp store_collected_snapshot(
         execution,
         %StudyPhase{snapshot_id: current_snapshot_id} = phase,
         snapshot_id
       )
       when is_nil(current_snapshot_id) or current_snapshot_id == snapshot_id do
    update_phase!(phase, %{snapshot_id: snapshot_id})
    transition_execution!(execution, :pilot_collected)
  end

  defp store_collected_snapshot(_execution, _phase, _snapshot_id) do
    Repo.rollback({:error, StudyError.collection_workflow_failed()})
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

  defp begin_final_analysis(execution_id, snapshot_id) do
    case transaction(&begin_final_analysis_transition(&1, snapshot_id), execution_id) do
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
         snapshot_id
       ) do
    phase = lock_named_phase(execution.id, :final_collection)

    if is_nil(phase.snapshot_id) or phase.snapshot_id == snapshot_id do
      update_phase!(phase, %{snapshot_id: snapshot_id})
      transitioned = transition_execution!(execution, :final_collected)
      insert_final_analysis_phase!(execution.id)
      transitioned
    else
      Repo.rollback({:error, StudyError.final_collection_workflow_failed()})
    end
  end

  defp begin_final_analysis_transition(%StudyExecution{state: state}, _snapshot_id),
    do: stop(state)

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
  defp workflow_error(:collecting_final), do: StudyError.final_collection_workflow_failed()
  defp workflow_error(:analyzing_final), do: StudyError.final_analysis_failed()

  defp bounded_pilot_error(%StudyError{} = error), do: error
  defp bounded_pilot_error(%PilotError{}), do: StudyError.pilot_analysis_failed()
  defp bounded_pilot_error(_reason), do: StudyError.pilot_analysis_failed()

  defp bounded_final_error(%StudyError{} = error), do: error
  defp bounded_final_error(%FinalError{}), do: StudyError.final_analysis_failed()
  defp bounded_final_error(_reason), do: StudyError.final_analysis_failed()
end
