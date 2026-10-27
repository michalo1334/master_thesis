defmodule NetworkDefense.Evaluation.Study.Actions.CheckFinalEnvironment do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Revisions
  alias NetworkDefense.Evaluation.Study.TaskFailure
  alias NetworkDefense.Evaluation.Study.Timing.Environment
  alias NetworkDefense.Evaluation.StudyExecution
  alias NetworkDefense.Evaluation.StudyPhase
  alias NetworkDefense.Evaluation.StudyPhaseRun
  alias NetworkDefense.Repo

  @impl true
  def execute(args, _context) do
    with {:ok, phase_run_id} <- phase_run_id(args),
         {:ok, phase_run} <- load_phase_run(phase_run_id),
         {:ok, phase} <- load_phase(phase_run.study_phase_id),
         {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         :ok <- matches(definition.study.revisions.environment) do
      %{"study_phase_run_id" => phase_run.id}
    else
      {:error, %StudyError{} = error} -> TaskFailure.raise_permanent(error)
    end
  end

  defp phase_run_id(args) do
    case Keyword.fetch(args, :study_phase_run_id) do
      {:ok, value} ->
        case Ecto.UUID.cast(value) do
          {:ok, id} -> {:ok, id}
          :error -> {:error, StudyError.invalid_study_phase()}
        end

      :error ->
        {:error, StudyError.invalid_study_phase()}
    end
  end

  defp load_phase_run(id) do
    case Repo.get(StudyPhaseRun, id) do
      %StudyPhaseRun{} = phase_run -> {:ok, phase_run}
      nil -> {:error, StudyError.phase_run_storage_failed()}
    end
  end

  defp load_phase(id) do
    case Repo.get(StudyPhase, id) do
      %StudyPhase{phase: :final_collection} = phase -> {:ok, phase}
      %StudyPhase{} -> {:error, StudyError.invalid_study_phase()}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp load_execution(id) do
    case Repo.get(StudyExecution, id) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp matches(declared) do
    case Environment.matches(
           declared,
           Application.get_env(:network_defense, :measured_environment_revision)
         ) do
      :ok -> :ok
      {:error, :missing_environment} -> {:error, StudyError.measured_environment_unavailable()}
      {:error, :environment_mismatch} -> {:error, StudyError.measured_environment_changed()}
    end
  end
end
