defmodule NetworkDefense.Evaluation.Study.Cancel do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Lifecycle
  alias NetworkDefense.Evaluation.StudyExecution
  alias NetworkDefense.Repo

  # Cancellation of one study execution.
  #
  # The locked row makes cancellation win over late completion: a coordinator
  # that finishes after this command finds the cancelled state and stops. A
  # repeated cancellation returns the stored row. A succeeded or failed
  # execution keeps its state, because its result is already authoritative.
  #
  # No Gust run, optimization, simulation, or task is cancelled here. The
  # existing locked coordinator boundaries make cancellation win instead.

  @terminal_states [:succeeded, :failed]

  @spec cancel(Ecto.UUID.t()) :: {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def cancel(execution_id) do
    with {:ok, id} <- cast_execution_id(execution_id) do
      id |> cancel_transaction() |> transaction_result()
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.study_execution_storage_failed()}
  end

  defp cast_execution_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp cancel_transaction(execution_id) do
    Repo.transaction(fn ->
      execution_id |> lock_execution() |> unwrap() |> cancel_locked() |> unwrap()
    end)
  end

  defp lock_execution(execution_id) do
    case Repo.one(
           from execution in StudyExecution,
             where: execution.id == ^execution_id,
             lock: "FOR UPDATE"
         ) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp cancel_locked(%StudyExecution{state: :cancelled} = execution), do: {:ok, execution}

  defp cancel_locked(%StudyExecution{state: state})
       when state in @terminal_states,
       do: {:error, StudyError.study_execution_not_cancellable()}

  defp cancel_locked(%StudyExecution{state: state} = execution) do
    case Lifecycle.transition(state, :cancel) do
      {:ok, :cancelled} -> store_cancelled(execution)
      _invalid -> {:error, StudyError.study_execution_not_cancellable()}
    end
  end

  defp store_cancelled(execution) do
    execution
    |> StudyExecution.changeset(%{state: :cancelled})
    |> Repo.update()
    |> case do
      {:ok, %StudyExecution{} = cancelled} -> {:ok, cancelled}
      {:error, _changeset} -> {:error, StudyError.study_execution_storage_failed()}
    end
  end

  defp transaction_result({:ok, %StudyExecution{} = execution}), do: {:ok, execution}
  defp transaction_result({:error, %StudyError{} = error}), do: {:error, error}
  defp transaction_result(_result), do: {:error, StudyError.study_execution_storage_failed()}

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, %StudyError{} = error}), do: Repo.rollback(error)
end
