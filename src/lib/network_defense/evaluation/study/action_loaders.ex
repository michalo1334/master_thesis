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
end
