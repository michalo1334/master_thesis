defmodule NetworkDefense.Evaluation.Study.ActionLoaders do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyPhase
  alias NetworkDefense.Repo

  @spec final_phase(Ecto.UUID.t()) :: {:ok, StudyPhase.t()} | {:error, StudyError.t()}
  def final_phase(id) do
    case Repo.get(StudyPhase, id) do
      %StudyPhase{phase: :final_collection} = phase -> {:ok, phase}
      %StudyPhase{} -> {:error, StudyError.invalid_study_phase()}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  # Pilot reads the run parameter without a Final-style collection-phase guard.
  @spec pilot_phase_for_run(integer()) :: {:ok, StudyPhase.t()} | {:error, StudyError.t()}
  def pilot_phase_for_run(run_id) do
    with %{params: %{"study_phase_id" => phase_id}} <- Gust.Flows.get_run!(run_id),
         {:ok, id} <- Ecto.UUID.cast(phase_id),
         %StudyPhase{} = phase <- Repo.get(StudyPhase, id) do
      {:ok, phase}
    else
      _invalid -> {:error, StudyError.invalid_study_phase()}
    end
  end
end
