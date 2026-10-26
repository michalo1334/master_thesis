defmodule NetworkDefense.Evaluation.Study.Start do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{Coordinator, Lifecycle, Revisions}
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  # Creation of one study execution from one stored revision.
  #
  # The execution and its Pilot collection phase join the database in one
  # transaction. Only a committed row set starts the ephemeral coordinator, so a
  # coordinator-start failure keeps the created rows. This matches the existing
  # resume boundary and the prototype recovery policy: no outbox, no cleanup
  # transaction, no retry, and no recovery worker.
  #
  # The optional coordinator exists for focused coordinator-start tests. The
  # public facade calls the one-argument form.

  @spec start(Ecto.UUID.t(), keyword()) ::
          {:ok, StudyExecution.t()} | {:error, StudyError.t()}
  def start(revision_id, opts \\ []) do
    coordinator = Keyword.get(opts, :coordinator, Coordinator)

    with {:ok, execution} <- revision_id |> create_transaction() |> transaction_result(),
         {:ok, _pid} <- coordinator.start(execution.id) do
      {:ok, execution}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.study_execution_storage_failed()}
  end

  defp create_transaction(revision_id) do
    Repo.transaction(fn ->
      _definition = revision_id |> Revisions.load_definition() |> unwrap()
      execution = revision_id |> insert_execution() |> unwrap()
      _pilot_phase = execution |> insert_pilot_phase() |> unwrap()
      execution
    end)
  end

  defp insert_execution(revision_id) do
    %StudyExecution{}
    |> StudyExecution.changeset(%{
      study_revision_id: revision_id,
      state: Lifecycle.initial_state()
    })
    |> Repo.insert()
    |> case do
      {:ok, %StudyExecution{} = execution} -> {:ok, execution}
      {:error, _changeset} -> {:error, StudyError.study_execution_storage_failed()}
    end
  end

  defp insert_pilot_phase(%StudyExecution{} = execution) do
    %StudyPhase{}
    |> StudyPhase.changeset(%{execution_id: execution.id, phase: :pilot_collection})
    |> Repo.insert()
    |> case do
      {:ok, %StudyPhase{} = phase} -> {:ok, phase}
      {:error, _changeset} -> {:error, StudyError.study_execution_storage_failed()}
    end
  end

  defp transaction_result({:ok, %StudyExecution{} = execution}), do: {:ok, execution}
  defp transaction_result({:error, %StudyError{} = error}), do: {:error, error}
  defp transaction_result(_result), do: {:error, StudyError.study_execution_storage_failed()}

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, %StudyError{} = error}), do: Repo.rollback(error)
end
