defmodule NetworkDefense.Evaluation.Study.Pipeline.State do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{ExecutionAccess, Lifecycle}
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  # Execution-scoped persistence primitives.
  #
  # Every mutation runs under the execution row lock, so a stale coordinator
  # cannot accept a run or a result after cancellation. Waiting for Gust stays
  # outside these locks.

  @spec transaction(Ecto.UUID.t(), (StudyExecution.t() -> term())) :: term()
  def transaction(execution_id, function) do
    result =
      Repo.transaction(fn ->
        case ExecutionAccess.lock(execution_id) do
          %StudyExecution{} = execution -> function.(execution)
          nil -> Repo.rollback({:error, StudyError.study_execution_not_found()})
        end
      end)

    case result do
      {:ok, value} -> value
      {:error, value} -> value
    end
  end

  # The stored state is authoritative after a wait. A cancelled or advanced study
  # stops the stage instead of finishing work it no longer owns.
  @spec require_state(Ecto.UUID.t(), atom()) :: :ok | {:stop, atom()}
  def require_state(execution_id, expected_state) do
    transaction(execution_id, fn execution ->
      if execution.state == expected_state, do: :ok, else: stop(execution.state)
    end)
  end

  @spec lock_phase(Ecto.UUID.t()) :: StudyPhase.t()
  def lock_phase(phase_id) do
    Repo.one!(from phase in StudyPhase, where: phase.id == ^phase_id, lock: "FOR UPDATE")
  end

  @spec lock_named_phase(Ecto.UUID.t(), atom()) :: StudyPhase.t()
  def lock_named_phase(execution_id, phase_name) do
    Repo.one!(
      from phase in StudyPhase,
        where: phase.execution_id == ^execution_id and phase.phase == ^phase_name,
        lock: "FOR UPDATE"
    )
  end

  @spec update_phase!(StudyPhase.t(), map()) :: StudyPhase.t()
  def update_phase!(phase, attrs), do: phase |> StudyPhase.changeset(attrs) |> Repo.update!()

  @spec transition!(StudyExecution.t(), Lifecycle.event()) :: StudyExecution.t()
  def transition!(%StudyExecution{} = execution, event) do
    {:ok, state} = Lifecycle.transition(execution.state, event)
    execution |> StudyExecution.changeset(%{state: state}) |> Repo.update!()
  end

  @spec stop(atom()) :: no_return()
  def stop(state), do: Repo.rollback({:stop, state})

  @spec phase_name(atom()) :: atom()
  def phase_name(:collecting_pilot), do: :pilot_collection
  def phase_name(:analyzing_pilot), do: :pilot_analysis
  def phase_name(:collecting_final), do: :final_collection
  def phase_name(:analyzing_final), do: :final_analysis

  @spec state_error(atom()) :: StudyError.t()
  def state_error(:collecting_pilot), do: StudyError.collection_workflow_failed()
  def state_error(:analyzing_pilot), do: StudyError.pilot_analysis_failed()
  def state_error(:collecting_final), do: StudyError.final_collection_workflow_failed()
  def state_error(:analyzing_final), do: StudyError.final_analysis_failed()

  # One phase owns one Gust run. A phase that already links the same run keeps
  # it, so a repeated coordination attempt never creates a second run.
  @spec accept_run(Ecto.UUID.t(), atom(), StudyPhase.t(), integer()) ::
          :ok | {:stop, atom()} | {:error, StudyError.t()}
  def accept_run(execution_id, expected_state, %StudyPhase{id: phase_id}, run_id) do
    transaction(execution_id, &accept_locked_run(&1, expected_state, phase_id, run_id))
  end

  @spec dispatch_run(Ecto.UUID.t(), atom(), StudyPhase.t(), integer(), module()) ::
          :ok | {:stop, atom()} | {:error, StudyError.t()}
  def dispatch_run(execution_id, expected_state, %StudyPhase{id: phase_id}, run_id, workflow) do
    transaction(
      execution_id,
      &dispatch_locked_run(&1, expected_state, phase_id, run_id, workflow)
    )
  end

  defp accept_locked_run(%StudyExecution{state: state}, expected_state, phase_id, run_id)
       when state == expected_state do
    phase = lock_phase(phase_id)

    case phase.gust_run_id do
      nil ->
        update_phase!(phase, %{gust_run_id: run_id})
        :ok

      ^run_id ->
        :ok

      _different_run_id ->
        Repo.rollback({:error, state_error(expected_state)})
    end
  end

  defp accept_locked_run(%StudyExecution{state: state}, _expected_state, _phase_id, _run_id) do
    stop(state)
  end

  defp dispatch_locked_run(
         %StudyExecution{state: state},
         expected_state,
         phase_id,
         run_id,
         workflow
       )
       when state == expected_state do
    phase = lock_phase(phase_id)
    dispatch_accepted_run(phase.gust_run_id, run_id, workflow, expected_state)
  end

  defp dispatch_locked_run(
         %StudyExecution{state: state},
         _expected_state,
         _phase_id,
         _run_id,
         _workflow
       ) do
    stop(state)
  end

  defp dispatch_accepted_run(accepted_run_id, run_id, workflow, expected_state)
       when accepted_run_id == run_id do
    case workflow.dispatch(run_id) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback({:error, reason})
      _invalid -> Repo.rollback({:error, state_error(expected_state)})
    end
  end

  defp dispatch_accepted_run(_accepted_run_id, _run_id, _workflow, expected_state) do
    Repo.rollback({:error, state_error(expected_state)})
  end
end
