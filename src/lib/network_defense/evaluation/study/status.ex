defmodule NetworkDefense.Evaluation.Study.Status do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyExecution
  alias NetworkDefense.Repo

  # The study status read boundary.
  #
  # Only the execution row is read. Phase rows, evidence snapshots, collection
  # items, and Gust records stay outside this read, because the execution row
  # supplies the whole prototype status.

  @spec get(Ecto.UUID.t()) :: {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def get(execution_id) do
    with {:ok, id} <- Ecto.UUID.cast(execution_id),
         %StudyExecution{} = execution <- Repo.get(StudyExecution, id) do
      {:ok, execution}
    else
      _not_found -> {:error, StudyError.study_execution_not_found()}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.study_execution_storage_failed()}
  end
end
