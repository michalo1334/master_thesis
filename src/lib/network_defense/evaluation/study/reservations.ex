defmodule NetworkDefense.Evaluation.Study.Reservations do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyCollectionItem
  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulations

  # The runtime reservation boundary of one collection item.
  #
  # A retry returns the linked record unchanged, and creation validates the
  # canonical request before the first link. The item row is locked for one
  # short transaction that holds no computation.

  @spec reserve_optimization(Ecto.UUID.t(), RunOptimizationRequest.t()) ::
          {:ok, OptimizationRun.t()} | {:error, StudyError.t()}
  def reserve_optimization(item_id, %RunOptimizationRequest{} = request) do
    case Optimizations.prepare_candidate(request) do
      {:ok, _graph, candidate} ->
        transaction(item_id, &reserve_optimization_locked(&1, candidate))

      {:error, reason} ->
        {:error, candidate_failure(:optimization_run_id, reason)}
    end
  end

  @spec reserve_experiment(Ecto.UUID.t(), RunSimulationRequest.t()) ::
          {:ok, Experiment.t()} | {:error, StudyError.t()}
  def reserve_experiment(item_id, %RunSimulationRequest{} = request) do
    case Simulations.prepare_candidate(request) do
      {:ok, candidate} ->
        transaction(item_id, &reserve_experiment_locked(&1, candidate))

      {:error, reason} ->
        {:error, candidate_failure(:experiment_id, reason)}
    end
  end

  defp transaction(item_id, reserved) do
    case Ecto.UUID.cast(item_id) do
      {:ok, id} -> run_transaction(id, reserved)
      :error -> {:error, StudyError.collection_item_not_found()}
    end
  end

  defp run_transaction(id, reserved) do
    Repo.transaction(fn -> lock_and_reserve(id, reserved) end)
    |> unwrap()
  end

  defp lock_and_reserve(id, reserved) do
    case lock_item(id) do
      nil -> Repo.rollback({:error, StudyError.collection_item_not_found()})
      %StudyCollectionItem{} = item -> reserved.(item)
    end
  end

  defp unwrap({:ok, {:ok, record}}), do: {:ok, record}
  defp unwrap({:error, {:error, %StudyError{} = error}}), do: {:error, error}

  defp candidate_failure(field, reason),
    do: StudyError.runtime_request_invalid(field, reason)

  defp lock_item(id) do
    Repo.one(from item in StudyCollectionItem, where: item.id == ^id, lock: "FOR UPDATE")
  end

  defp reserve_optimization_locked(
         %StudyCollectionItem{optimization_run_id: nil} = item,
         %OptimizationRun{} = candidate
       ) do
    case OptimizationRuns.create(candidate) do
      {:ok, %OptimizationRun{} = run} ->
        :ok = link(item, %{optimization_run_id: run.id})
        {:ok, run}

      {:error, _changeset} ->
        Repo.rollback({:error, StudyError.collection_item_storage_failed()})
    end
  end

  defp reserve_optimization_locked(
         %StudyCollectionItem{optimization_run_id: run_id},
         _candidate
       ) do
    case Repo.get(OptimizationRun, run_id) do
      %OptimizationRun{} = run ->
        {:ok, run}

      nil ->
        Repo.rollback(
          {:error, StudyError.runtime_record_unavailable(:optimization_run_id, :not_found)}
        )
    end
  end

  defp reserve_experiment_locked(
         %StudyCollectionItem{experiment_id: nil} = item,
         %Experiment{} = candidate
       ) do
    case Experiments.create(candidate) do
      {:ok, %Experiment{} = experiment} ->
        :ok = link(item, %{experiment_id: experiment.id})
        {:ok, experiment}

      {:error, _changeset} ->
        Repo.rollback({:error, StudyError.collection_item_storage_failed()})
    end
  end

  defp reserve_experiment_locked(
         %StudyCollectionItem{experiment_id: experiment_id},
         _candidate
       ) do
    case Experiments.get(experiment_id) do
      %Experiment{} = experiment ->
        {:ok, experiment}

      nil ->
        Repo.rollback({:error, StudyError.runtime_record_unavailable(:experiment_id, :not_found)})
    end
  end

  defp link(item, attrs) do
    case item |> StudyCollectionItem.link_changeset(attrs) |> Repo.update() do
      {:ok, %StudyCollectionItem{}} -> :ok
      {:error, _changeset} -> Repo.rollback({:error, StudyError.collection_item_storage_failed()})
    end
  end
end
