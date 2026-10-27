defmodule NetworkDefense.Evaluation.Study.Actions.MarkFinalTimingBoundary do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.TaskFailure
  alias NetworkDefense.Evaluation.StudyPhase
  alias NetworkDefense.Evaluation.StudyPhaseRun
  alias NetworkDefense.Repo

  @ack_timeout 5_000
  @events [:plan_dispatch, :plan_completion, :simulation_dispatch, :simulation_completion]

  @impl true
  def execute(args, _context) do
    with {:ok, phase_run_id} <- uuid_arg(args, :study_phase_run_id),
         {:ok, replica_position} <- position_arg(args),
         {:ok, event_kind} <- event_arg(args),
         {:ok, phase_run} <- load_phase_run(phase_run_id),
         {:ok, phase} <- load_phase(phase_run.study_phase_id),
         {:ok, execution_id} <- execution_id(phase),
         :ok <- send_marker(execution_id, phase_run_id, replica_position, event_kind) do
      %{"study_phase_run_id" => phase_run_id, "replica_position" => replica_position}
    else
      {:error, %StudyError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp uuid_arg(args, key) do
    case Keyword.fetch(args, key) do
      {:ok, value} ->
        case Ecto.UUID.cast(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, StudyError.final_timing_invalid()}
        end

      :error ->
        {:error, StudyError.final_timing_invalid()}
    end
  end

  defp position_arg(args) do
    case Keyword.fetch(args, :replica_position) do
      {:ok, position} when is_integer(position) and position in 0..4 -> {:ok, position}
      _ -> {:error, StudyError.final_timing_invalid()}
    end
  end

  defp event_arg(args) do
    case Keyword.fetch(args, :event_kind) do
      {:ok, event} when event in @events ->
        {:ok, event}

      {:ok, event} when is_binary(event) ->
        case event do
          "plan_dispatch" -> {:ok, :plan_dispatch}
          "plan_completion" -> {:ok, :plan_completion}
          "simulation_dispatch" -> {:ok, :simulation_dispatch}
          "simulation_completion" -> {:ok, :simulation_completion}
          _ -> {:error, StudyError.final_timing_invalid()}
        end

      _ ->
        {:error, StudyError.final_timing_invalid()}
    end
  end

  defp load_phase_run(id) do
    case Repo.get(StudyPhaseRun, id) do
      %StudyPhaseRun{} = phase_run -> {:ok, phase_run}
      nil -> {:error, StudyError.final_timing_unavailable()}
    end
  end

  defp load_phase(id) do
    case Repo.get(StudyPhase, id) do
      %StudyPhase{phase: :final_collection} = phase -> {:ok, phase}
      %StudyPhase{} -> {:error, StudyError.final_timing_invalid()}
      nil -> {:error, StudyError.final_timing_unavailable()}
    end
  end

  defp execution_id(%StudyPhase{execution_id: execution_id}) when is_binary(execution_id),
    do: {:ok, execution_id}

  defp execution_id(_phase), do: {:error, StudyError.final_timing_invalid()}

  defp send_marker(execution_id, phase_run_id, position, event_kind) do
    marker_ref = make_ref()
    marker_pid = self()

    case Registry.lookup(NetworkDefense.Evaluation.Study.CoordinatorRegistry, execution_id) do
      [{coordinator, _value} | _] when is_pid(coordinator) ->
        send(
          coordinator,
          {:final_timing_boundary, marker_ref, execution_id, phase_run_id, position, event_kind,
           marker_pid}
        )

        receive do
          {:final_timing_boundary_ack, ^marker_ref, :ok} ->
            :ok

          {:final_timing_boundary_ack, ^marker_ref, {:error, %StudyError{} = error}} ->
            {:error, error}

          {:final_timing_boundary_ack, ^marker_ref, {:error, _reason}} ->
            {:error, StudyError.final_timing_invalid()}
        after
          @ack_timeout -> {:error, StudyError.final_timing_unavailable()}
        end

      _ ->
        {:error, StudyError.final_timing_unavailable()}
    end
  rescue
    ArgumentError -> {:error, StudyError.final_timing_unavailable()}
  catch
    :exit, _reason -> {:error, StudyError.final_timing_unavailable()}
  end
end
