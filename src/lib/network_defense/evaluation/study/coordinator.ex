defmodule NetworkDefense.Evaluation.Study.Coordinator do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis, as: FinalAnalysis
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Analysis.IO, as: FinalAnalysisIO
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection, as: FinalCollection
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Analysis, as: PilotAnalysis
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection, as: PilotCollection
  alias NetworkDefense.Evaluation.Study.Pipeline.State

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.ExecutionAccess
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
      {:ok, :analyzing_final} -> resume_final(execution_id, opts)
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
    collection = Keyword.get(opts, :pilot_collection, PilotCollection)
    analysis = Keyword.get(opts, :pilot_workflow, PilotAnalysis.Workflow)

    result =
      with {:ok, collection_io} <- PilotCollection.IO.load(execution_id),
           {:ok, %PilotAnalysis.IO{} = analysis_io} <-
             collection.run(collection_io, Keyword.take(opts, [:workflow])),
           {:ok, :paused} <- PilotAnalysis.run(analysis_io, workflow: analysis) do
        :ok
      end

    finish_run(execution_id, result, &as_study_error/1)
  end

  # Final collection ends in the Final analysis stage. The analysis stage owns
  # the accepted run, the wait, and the result persistence, so the coordinator
  # only composes the two stages.
  defp run_final(execution_id, opts) do
    collection = Keyword.get(opts, :final_collection, FinalCollection)

    result =
      with {:ok, collection_io} <- FinalCollection.IO.load(execution_id),
           {:ok, %FinalAnalysisIO{} = analysis_io} <-
             collection.run(collection_io, collection_opts(opts)) do
        FinalAnalysis.run(analysis_io, analysis_opts(opts))
      end

    finish_run(execution_id, result, &bounded_final_error/1)
  end

  # A resumed coordination reuses the accepted Final analysis run. Repeated
  # entry after completion is a terminal no-op.
  defp resume_final(execution_id, opts) do
    result =
      with {:ok, %FinalAnalysisIO{} = analysis_io} <- FinalAnalysisIO.load(execution_id) do
        FinalAnalysis.run(analysis_io, analysis_opts(opts))
      end

    finish_run(execution_id, result, &bounded_final_error/1)
  end

  # The collection stage keeps the injected tier workflow, snapshot, and timeout.
  defp collection_opts(opts) do
    [
      workflow: Keyword.get(opts, :final_tier_workflow, FinalCollection.Workflow),
      snapshot: Keyword.get(opts, :final_snapshot, FinalCollection.Snapshot),
      timeout: Keyword.get(opts, :final_tier_timeout, :infinity)
    ]
  end

  # The analysis stage keeps the injected Final workflow and its wait timeout.
  defp analysis_opts(opts) do
    [
      workflow: Keyword.get(opts, :final_workflow, FinalAnalysis.Workflow),
      timeout: Keyword.get(opts, :final_analysis_timeout, :infinity)
    ]
  end

  defp finish_run(_execution_id, {:ok, _outcome}, _mapper), do: :ok
  defp finish_run(_execution_id, {:stop, _state}, _mapper), do: :ok

  defp finish_run(execution_id, {:error, reason}, mapper) do
    error = mapper.(reason)
    fail_active(execution_id, error)
    {:error, error}
  end

  defp current_state(execution_id) do
    case ExecutionAccess.fetch(execution_id) do
      {:ok, execution} -> {:ok, execution.state}
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
    with {:ok, execution} <- ExecutionAccess.fetch(execution_id),
         true <- execution.state == expected_state,
         %StudyPhase{} = phase <-
           Repo.get_by(
             StudyPhase,
             execution_id: execution.id,
             phase: State.phase_name(expected_state)
           ),
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

  defp fail_active(execution_id, %StudyError{} = error) do
    params = StudyError.to_params(error)

    State.transaction(execution_id, fn execution ->
      case execution.state do
        state
        when state in [
               :collecting_pilot,
               :analyzing_pilot,
               :collecting_final,
               :analyzing_final
             ] ->
          phase = State.lock_named_phase(execution.id, State.phase_name(state))
          State.update_phase!(phase, %{error: params})

          execution
          |> StudyExecution.changeset(%{error: params})
          |> Repo.update!()
          |> State.transition!(:fail)

          :ok

        _cancelled_or_terminal ->
          :ok
      end
    end)
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
        State.phase_name(state)

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

  # The Pilot stages expose study failures only, so the coordinator keeps one
  # bounded error family.
  defp as_study_error(%StudyError{} = error), do: error
  defp as_study_error(_reason), do: StudyError.pilot_analysis_failed()

  # The Final stages expose study failures only, so the coordinator keeps one
  # bounded error family.
  defp bounded_final_error(%StudyError{} = error), do: error
  defp bounded_final_error(_reason), do: StudyError.final_analysis_failed()
end
