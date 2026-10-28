defmodule NetworkDefense.Evaluation.Study.Status do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.ExecutionAccess
  alias NetworkDefense.Evaluation.StudyExecution

  # The study status read boundary.
  #
  # Only the execution row is read. Phase rows, evidence snapshots, collection
  # items, and Gust records stay outside this read, because the execution row
  # supplies the whole prototype status.

  @spec get(Ecto.UUID.t()) :: {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def get(execution_id) do
    ExecutionAccess.fetch(execution_id)
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.study_execution_storage_failed()}
  end
end
