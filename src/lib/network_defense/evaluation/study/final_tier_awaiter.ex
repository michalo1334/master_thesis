defmodule NetworkDefense.Evaluation.Study.FinalTierAwaiter do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.GustWaiter
  alias NetworkDefense.Evaluation.Study.Timing.Recorder
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyPhaseRun}
  alias NetworkDefense.Repo

  @events [:plan_dispatch, :plan_completion, :simulation_dispatch, :simulation_completion]

  @spec await(StudyExecution.t(), StudyPhaseRun.t(), timeout()) ::
          {:ok, [NetworkDefense.Evaluation.Study.Timing.ReplicaTiming.t()]}
          | {:error, StudyError.t()}
  def await(
        %StudyExecution{id: execution_id} = execution,
        %StudyPhaseRun{gust_run_id: run_id, tier: tier, id: phase_run_id} = phase_run,
        timeout
      )
      when is_binary(execution_id) and is_binary(tier) and is_binary(phase_run_id) and
             is_integer(run_id) and run_id > 0 and
             (timeout == :infinity or (is_integer(timeout) and timeout >= 0)) do
    deadline = deadline(timeout)

    with :ok <- validate_identity(execution, phase_run) do
      wait_for_run(execution, phase_run, deadline)
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_timing_unavailable()}
  end

  def await(_execution, _phase_run, _timeout),
    do: {:error, StudyError.final_timing_unavailable()}

  defp wait_for_run(
         execution,
         %StudyPhaseRun{gust_run_id: run_id, tier: tier} = phase_run,
         deadline
       ) do
    parent = self()
    reference = make_ref()

    {helper, monitor} =
      spawn_monitor(fn ->
        result = GustWaiter.await(run_id, remaining(deadline))
        send(parent, {:final_tier_gust_result, reference, result})
      end)

    loop(execution, phase_run, Recorder.new(tier), deadline, helper, monitor, reference)
  end

  defp validate_identity(%StudyExecution{id: execution_id}, %StudyPhaseRun{} = phase_run) do
    with {:ok, execution_id} <- Ecto.UUID.cast(execution_id),
         {:ok, phase_run_id} <- Ecto.UUID.cast(phase_run.id),
         %StudyPhaseRun{} = stored <- Repo.get(StudyPhaseRun, phase_run_id),
         true <-
           Map.take(stored, [:study_phase_id, :tier, :tier_position, :gust_run_id]) ==
             Map.take(phase_run, [:study_phase_id, :tier, :tier_position, :gust_run_id]),
         %StudyPhase{phase: :final_collection, execution_id: ^execution_id} <-
           Repo.get(StudyPhase, stored.study_phase_id),
         true <- String.trim(stored.tier) != "" do
      :ok
    else
      _ -> {:error, StudyError.final_timing_invalid()}
    end
  end

  defp loop(
         execution,
         phase_run,
         recorder,
         deadline,
         helper,
         monitor,
         reference
       ) do
    if remaining(deadline) == 0 do
      terminate({:error, StudyError.final_timing_unavailable()}, helper, monitor, reference)
    else
      receive_result(execution, phase_run, recorder, deadline, helper, monitor, reference)
    end
  end

  defp receive_result(
         %StudyExecution{id: execution_id} = execution,
         phase_run,
         recorder,
         deadline,
         helper,
         monitor,
         reference
       ) do
    receive do
      {:final_timing_boundary, _marker_ref, _marker_execution, _phase_run_id, _position, _event,
       _marker_pid} = marker ->
        case handle_marker(execution, phase_run, recorder, marker) do
          {:continue, updated} ->
            loop(execution, phase_run, updated, deadline, helper, monitor, reference)

          {:stop, error} ->
            terminate(error, helper, monitor, reference)
        end

      {:final_tier_gust_result, ^reference, result} ->
        terminate(handle_gust_result(recorder, result), helper, monitor, reference)

      {:study_cancelled, ^execution_id} ->
        case cancellation_result(execution_id) do
          :continue -> loop(execution, phase_run, recorder, deadline, helper, monitor, reference)
          {:stop, error} -> terminate(error, helper, monitor, reference)
        end

      {:DOWN, ^monitor, :process, ^helper, _reason} ->
        terminate({:error, StudyError.final_timing_unavailable()}, helper, monitor, reference)
    after
      remaining(deadline) ->
        terminate({:error, StudyError.final_timing_unavailable()}, helper, monitor, reference)
    end
  end

  defp handle_marker(execution, phase_run, recorder, {
         :final_timing_boundary,
         marker_ref,
         marker_execution,
         phase_run_id,
         position,
         event,
         marker_pid
       }) do
    case validate_marker(
           execution,
           phase_run,
           marker_execution,
           phase_run_id,
           position,
           event,
           marker_pid
         ) do
      :ok ->
        case Recorder.record(recorder, phase_run.tier, position, event) do
          {:ok, updated} ->
            send(marker_pid, {:final_timing_boundary_ack, marker_ref, :ok})
            {:continue, updated}

          {:error, _reason, _failed} ->
            error = StudyError.final_timing_invalid()
            send(marker_pid, {:final_timing_boundary_ack, marker_ref, {:error, error}})
            {:stop, {:error, error}}
        end

      {:error, error} ->
        if is_pid(marker_pid),
          do: send(marker_pid, {:final_timing_boundary_ack, marker_ref, {:error, error}})

        {:stop, {:error, error}}
    end
  end

  defp handle_gust_result(recorder, {:ok, :succeeded}) do
    case Recorder.complete(recorder) do
      {:ok, timings} -> {:ok, timings}
      {:error, :incomplete} -> {:error, StudyError.final_timing_incomplete()}
      {:error, _reason} -> {:error, StudyError.final_timing_invalid()}
    end
  end

  defp handle_gust_result(_recorder, {:error, reason}) when reason in [:failed, :not_found],
    do: {:error, StudyError.final_collection_workflow_failed()}

  defp handle_gust_result(_recorder, {:error, :timeout}),
    do: {:error, StudyError.final_timing_unavailable()}

  defp handle_gust_result(_recorder, {:error, :unavailable}),
    do: {:error, StudyError.final_timing_unavailable()}

  defp handle_gust_result(_recorder, _result),
    do: {:error, StudyError.final_timing_unavailable()}

  defp cancellation_result(execution_id) do
    case Repo.get(StudyExecution, execution_id) do
      %StudyExecution{state: :cancelled} ->
        reject_pending_markers()
        {:stop, {:error, StudyError.final_collection_workflow_failed()}}

      _ ->
        :continue
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:stop, {:error, StudyError.study_execution_storage_failed()}}
  end

  defp validate_marker(
         %StudyExecution{id: expected_execution},
         %StudyPhaseRun{id: expected_phase_run},
         expected_execution,
         expected_phase_run,
         position,
         event,
         marker_pid
       )
       when is_pid(marker_pid) and is_integer(position) and position in 0..4 and event in @events,
       do: :ok

  defp validate_marker(
         _execution,
         _phase_run,
         _execution_id,
         _phase_run_id,
         _position,
         _event,
         _pid
       ),
       do: {:error, StudyError.final_timing_invalid()}

  defp terminate(result, helper, monitor, reference) do
    stop_helper(helper, monitor)

    receive do
      {:final_tier_gust_result, ^reference, _result} -> :ok
    after
      0 -> :ok
    end

    reject_pending_markers()
    result
  end

  defp stop_helper(helper, monitor) do
    if Process.alive?(helper), do: Process.exit(helper, :shutdown)

    receive do
      {:DOWN, ^monitor, :process, ^helper, _reason} -> :ok
    after
      100 -> Process.demonitor(monitor, [:flush])
    end
  end

  defp reject_pending_markers do
    receive do
      {:final_timing_boundary, marker_ref, _execution_id, _phase_run_id, _position, _event,
       marker_pid}
      when is_pid(marker_pid) ->
        send(marker_pid, {
          :final_timing_boundary_ack,
          marker_ref,
          {:error, StudyError.final_timing_unavailable()}
        })

        reject_pending_markers()
    after
      0 -> :ok
    end
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp remaining(:infinity), do: :infinity

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
