defmodule NetworkDefense.Evaluation.Study.ExecutionAccess do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyExecution
  alias NetworkDefense.Repo

  @spec fetch(term()) :: {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def fetch(execution_id) do
    case Ecto.UUID.cast(execution_id) do
      {:ok, id} -> fetch_trusted(id)
      :error -> not_found()
    end
  end

  # Persisted IDs keep the raw Repo lookup semantics, without UUID normalization.
  @spec fetch_trusted(Ecto.UUID.t()) :: {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def fetch_trusted(execution_id) do
    StudyExecution |> Repo.get(execution_id) |> fetch_result()
  end

  # Callers own the transaction and acquire any phase locks after this row lock.
  @spec lock(term()) :: StudyExecution.t() | nil
  def lock(execution_id) do
    case Ecto.UUID.cast(execution_id) do
      {:ok, id} -> lock_trusted(id)
      :error -> nil
    end
  end

  @spec fetch_locked_trusted(Ecto.UUID.t()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def fetch_locked_trusted(execution_id) do
    execution_id |> lock_trusted() |> fetch_result()
  end

  defp lock_trusted(execution_id) do
    Repo.one(
      from execution in StudyExecution,
        where: execution.id == ^execution_id,
        lock: "FOR UPDATE"
    )
  end

  defp fetch_result(%StudyExecution{} = execution), do: {:ok, execution}
  defp fetch_result(nil), do: not_found()

  defp not_found, do: {:error, StudyError.study_execution_not_found()}
end
