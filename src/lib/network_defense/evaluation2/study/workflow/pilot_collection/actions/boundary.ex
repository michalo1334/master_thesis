defmodule NetworkDefense.Evaluation2.Study.Workflow.PilotCollection.Actions.Boundary do
  @moduledoc false

  # Shared boundary of the Pilot collection Gust tasks.
  #
  # Every task binds its work to the Gust run it executes. A static task requires
  # the stored run input to name the phase run linked to this run, and a mapped
  # task requires the collection item to belong to that phase run. The binding
  # proves ownership of the stored links; it does not re-derive the planned work.
  #
  # Every tagged failure is logged here and raised as one fixed permanent Gust
  # message by the action. The tagged helpers return the tagged result unchanged,
  # so each action keeps the complete declared result type of its capability.

  require Logger

  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun
  alias NetworkDefense.Evaluation2.Study.Pilot.CollectionContract

  @context_failure "Evaluation2 Pilot collection context is unavailable"
  @foreign_run_failure "Evaluation2 Pilot collection task acted for another Gust run"

  @spec run_context(map(), map()) ::
          {:ok, Persistence.phase_run_context()} | {:error, term()}
  def run_context(params, %{run_id: run_id}) do
    with {:ok, input} <- input(params),
         {:ok, context} <- phase_run_context(input.phase_run_id),
         :ok <- expect_run_id(context.phase_run, run_id) do
      {:ok, context}
    end
  end

  @spec run_item(term(), integer()) :: {:ok, CollectionItem.t()} | {:error, term()}
  def run_item(item_id, run_id) do
    with {:ok, item} <- collection_item(item_id),
         {:ok, phase_run} <- phase_run(item.study_phase_run_id),
         :ok <- expect_run_id(phase_run, run_id) do
      {:ok, item}
    end
  end

  @spec input(map()) :: {:ok, CollectionContract.Input.t()} | {:error, :invalid_input}
  def input(params) do
    case CollectionContract.decode_input(params) do
      {:ok, input} -> {:ok, input}
      :error -> {:error, :invalid_input}
    end
  end

  @spec phase_run_context(Ecto.UUID.t()) ::
          {:ok, Persistence.phase_run_context()} | {:error, term()}
  def phase_run_context(phase_run_id) do
    logged(@context_failure, Persistence.fetch_phase_run_context(phase_run_id))
  end

  @spec logged(String.t(), {:ok, value} | {:error, term()}) :: {:ok, value} | {:error, term()}
        when value: var
  def logged(message, result) do
    case result do
      {:ok, value} ->
        {:ok, value}

      {:error, cause} = failure ->
        Logger.error(message, cause: inspect(cause))
        failure
    end
  end

  @spec logged_status(String.t(), :ok | {:error, term()}) :: :ok | {:error, term()}
  def logged_status(message, result) do
    case result do
      :ok ->
        :ok

      {:error, cause} = failure ->
        Logger.error(message, cause: inspect(cause))
        failure
    end
  end

  defp collection_item(item_id) do
    logged(@context_failure, Persistence.Collection.fetch_collection_item(item_id))
  end

  defp phase_run(phase_run_id) do
    case phase_run_context(phase_run_id) do
      {:ok, context} -> {:ok, context.phase_run}
      {:error, _cause} = failure -> failure
    end
  end

  # The acting Gust run must own the stored phase-run link, so one task cannot
  # work for another run.
  @spec expect_run_id(PhaseRun.t(), term()) :: :ok | {:error, :foreign_run}
  defp expect_run_id(%PhaseRun{gust_run_id: run_id}, run_id), do: :ok

  defp expect_run_id(%PhaseRun{}, run_id) do
    Logger.error(@foreign_run_failure, run_id: run_id)
    {:error, :foreign_run}
  end
end
