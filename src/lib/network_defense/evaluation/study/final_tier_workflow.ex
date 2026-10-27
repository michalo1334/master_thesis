defmodule NetworkDefense.Evaluation.Study.FinalTierWorkflow do
  @moduledoc false

  alias Gust.DAG.Run.Trigger
  alias NetworkDefense.Evaluation.Study.{Collection, FinalTierAwaiter, Revisions}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyPhaseRun}
  alias NetworkDefense.Repo

  @dag_name "evaluation_study_final_tier_collection"
  @result_task "complete_final_tier"

  @spec create(StudyPhaseRun.t()) :: {:ok, integer()} | {:error, StudyError.t()}
  def create(%StudyPhaseRun{} = phase_run) do
    with :ok <- stored_phase_run(phase_run),
         {:ok, phase} <- load_final_phase(phase_run.study_phase_id),
         {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         :ok <- validate_phase_run(definition, phase_run),
         %{id: dag_id} <- Gust.Flows.get_dag_by_name(@dag_name),
         {:ok, run} <-
           Gust.Flows.create_run(%{
             dag_id: dag_id,
             params: run_params(phase_run, phase, execution)
           }) do
      {:ok, run.id}
    else
      {:error, %StudyError{} = error} -> {:error, error}
      _invalid -> {:error, StudyError.final_collection_workflow_failed()}
    end
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, StudyError.final_collection_workflow_failed()}
  end

  @spec dispatch(integer()) :: :ok | {:error, StudyError.t()}
  def dispatch(run_id) when is_integer(run_id) and run_id > 0 do
    run = Gust.Flows.get_run!(run_id)
    _dispatched = Trigger.dispatch_run(run)
    :ok
  rescue
    _exception -> {:error, StudyError.final_collection_workflow_failed()}
  end

  def dispatch(_run_id), do: {:error, StudyError.final_collection_workflow_failed()}

  @spec await(StudyExecution.t(), StudyPhaseRun.t(), timeout()) ::
          {:ok, [NetworkDefense.Evaluation.Study.Timing.ReplicaTiming.t()]}
          | {:error, StudyError.t()}
  def await(%StudyExecution{} = execution, %StudyPhaseRun{} = phase_run, timeout \\ :infinity) do
    case FinalTierAwaiter.await(execution, phase_run, timeout) do
      {:error, %StudyError{issues: issues}} = failure ->
        if Enum.any?(issues, &match?(%{"code" => "final_collection_workflow_failed"}, &1)),
          do: {:error, task_failure(phase_run.gust_run_id)},
          else: failure

      success ->
        success
    end
  end

  @spec result(integer()) :: {:ok, map()} | {:error, StudyError.t()}
  def result(run_id) when is_integer(run_id) and run_id > 0 do
    with %{status: :succeeded, params: params} <- Gust.Flows.get_run!(run_id),
         {:ok, expected} <- expected_identity(params, run_id),
         [%{status: :succeeded, result: result}] <-
           Gust.Flows.get_tasks_by_name(@result_task, run_id),
         {:ok, receipt} <- receipt(result),
         true <- receipt == expected do
      {:ok, receipt}
    else
      _invalid -> {:error, StudyError.final_collection_workflow_failed()}
    end
  rescue
    _exception -> {:error, StudyError.final_collection_workflow_failed()}
  end

  def result(_run_id), do: {:error, StudyError.final_collection_workflow_failed()}

  defp stored_phase_run(%StudyPhaseRun{id: id} = phase_run) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %StudyPhaseRun{} = stored <- Repo.get(StudyPhaseRun, id),
         true <-
           Map.take(stored, [:study_phase_id, :tier, :tier_position, :gust_run_id]) ==
             Map.take(phase_run, [:study_phase_id, :tier, :tier_position, :gust_run_id]) do
      :ok
    else
      _ -> {:error, StudyError.phase_run_conflict()}
    end
  end

  # Only known bounded task errors cross this boundary. Never return Gust diagnostics.
  defp task_failure(run_id) do
    run_id
    |> Gust.Flows.get_run_with_tasks!()
    |> Map.fetch!(:tasks)
    |> Enum.find_value(StudyError.final_collection_workflow_failed(), fn
      %{status: :failed, error: %{"message" => message}} -> bounded_task_error(message)
      _ -> nil
    end)
  rescue
    _exception -> StudyError.final_collection_workflow_failed()
  end

  defp bounded_task_error(message) when is_binary(message) do
    case Jason.decode(message) do
      {:ok,
       %{"kind" => "network_defense.evaluation.study_error", "version" => 1, "error" => params}} ->
        Enum.find(
          [
            StudyError.measured_environment_unavailable(),
            StudyError.measured_environment_changed(),
            StudyError.final_timing_unavailable(),
            StudyError.final_timing_invalid(),
            StudyError.final_timing_incomplete()
          ],
          &(StudyError.to_params(&1) == params)
        )

      _ ->
        nil
    end
  end

  defp bounded_task_error(_message), do: nil

  defp load_final_phase(id) do
    case Repo.get(StudyPhase, id) do
      %StudyPhase{phase: :final_collection} = phase -> {:ok, phase}
      %StudyPhase{} -> {:error, StudyError.invalid_study_phase()}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp load_execution(id) do
    case Repo.get(StudyExecution, id) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp validate_phase_run(definition, %StudyPhaseRun{tier: tier, tier_position: position})
       when is_integer(position) and position >= 0 do
    with {:ok, tiers} <- Collection.tier_order(definition),
         ^tier <- Enum.at(tiers, position) do
      :ok
    else
      _ -> {:error, StudyError.invalid_tier()}
    end
  end

  defp validate_phase_run(_definition, _phase_run), do: {:error, StudyError.invalid_tier()}

  defp run_params(
         %StudyPhaseRun{} = phase_run,
         %StudyPhase{} = phase,
         %StudyExecution{} = execution
       ) do
    %{
      "study_phase_run_id" => phase_run.id,
      "study_phase_id" => phase.id,
      "execution_id" => execution.id,
      "tier" => phase_run.tier,
      "tier_position" => phase_run.tier_position
    }
  end

  defp expected_identity(params, run_id) do
    with {:ok,
          %{"study_phase_run_id" => phase_run_id, "tier" => tier, "tier_position" => position} =
            identity} <- receipt(params),
         {:ok, phase_id} <- cast_uuid(params["study_phase_id"]),
         {:ok, execution_id} <- cast_uuid(params["execution_id"]),
         %StudyPhaseRun{
           study_phase_id: ^phase_id,
           tier: ^tier,
           tier_position: ^position,
           gust_run_id: ^run_id
         } <- Repo.get(StudyPhaseRun, phase_run_id),
         %StudyPhase{phase: :final_collection, execution_id: ^execution_id} <-
           Repo.get(StudyPhase, phase_id) do
      {:ok, identity}
    else
      _ -> :error
    end
  end

  defp receipt(%{
         "study_phase_run_id" => phase_run_id,
         "tier" => tier,
         "tier_position" => position
       }) do
    with {:ok, phase_run_id} <- cast_uuid(phase_run_id),
         tier when is_binary(tier) and byte_size(tier) > 0 <- tier,
         position when is_integer(position) and position >= 0 <- position do
      {:ok,
       %{
         "study_phase_run_id" => phase_run_id,
         "tier" => tier,
         "tier_position" => position
       }}
    else
      _ -> :error
    end
  end

  defp receipt(_result), do: :error

  defp cast_uuid(value), do: Ecto.UUID.cast(value)
end
