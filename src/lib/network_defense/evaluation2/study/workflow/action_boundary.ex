defmodule NetworkDefense.Evaluation2.Study.Workflow.ActionBoundary do
  @moduledoc false

  # Shared mechanics of the phase task boundaries.
  #
  # Every phase boundary logs its tagged failures and proves that a task acts only
  # for the Gust run it executes. Both mechanics are identical across phases, so
  # they live here. Each phase boundary keeps its own messages, persistence
  # reads, and codecs.
  #
  # The helpers return the tagged result unchanged, so each action keeps the
  # complete declared result type of its capability.

  require Logger

  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun

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

  # The canonical phase-run context of one task, read once per task.
  @spec phase_run_context(String.t(), Ecto.UUID.t()) ::
          {:ok, Persistence.phase_run_context()} | {:error, term()}
  def phase_run_context(message, phase_run_id) do
    logged(message, Persistence.fetch_phase_run_context(phase_run_id))
  end

  # The acting Gust run must own the stored phase-run link, so one task cannot
  # work for another run.
  @spec expect_run_id(PhaseRun.t(), term(), String.t()) :: :ok | {:error, :foreign_run}
  def expect_run_id(%PhaseRun{gust_run_id: run_id}, run_id, _message), do: :ok

  def expect_run_id(%PhaseRun{}, run_id, message) do
    Logger.error(message, run_id: run_id)
    {:error, :foreign_run}
  end
end
