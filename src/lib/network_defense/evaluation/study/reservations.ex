defmodule NetworkDefense.Evaluation.Study.Reservations do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyCollectionItem
  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimization.RunIdentity
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.ExperimentIdentity
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulations

  # The runtime reservation boundary of one collection item.
  #
  # One collection item carries two links: the optimization run and the
  # experiment that its task created. A reservation locks the item row for one
  # short transaction, then either creates one runtime record and links it, or
  # verifies the record that the item already links. The transaction holds no
  # computation, so no optimization, simulation, Task, ScatterGather, Gust, or
  # Oban work runs under the row lock.
  #
  # A repeated matching reservation returns the linked record, so a retried
  # collection attempt adds no second domain record. A linked record that does
  # not match the declared request fails with a bounded study error and keeps
  # its link, so a changed request cannot replace stored evidence.
  #
  # The caller sequence is: reserve the optimization run, compute outside the
  # transaction, derive the simulation request from the optimized graph, reserve
  # the experiment, and compute outside the transaction again.
  #
  # Optimization identity is the shared F1 rule in
  # `NetworkDefense.Optimization.RunIdentity`. Experiment identity is
  # `NetworkDefense.Simulation.ExperimentIdentity`. Both rules ignore the
  # correlation identifier, which is operational metadata.

  @spec reserve_optimization(Ecto.UUID.t(), RunOptimizationRequest.t()) ::
          {:ok, OptimizationRun.t()} | {:error, StudyError.t()}
  def reserve_optimization(item_id, %RunOptimizationRequest{} = request) do
    case Optimizations.prepare_candidate(request) do
      {:ok, _graph, candidate} ->
        transaction(item_id, &reserve_optimization_locked(&1, candidate, request))

      {:error, reason} ->
        {:error, candidate_failure(:optimization_run_id, reason)}
    end
  end

  @spec reserve_experiment(Ecto.UUID.t(), RunSimulationRequest.t()) ::
          {:ok, Experiment.t()} | {:error, StudyError.t()}
  def reserve_experiment(item_id, %RunSimulationRequest{} = request) do
    case Simulations.prepare_candidate(request) do
      {:ok, candidate} ->
        transaction(item_id, &reserve_experiment_locked(&1, candidate, request))

      {:error, reason} ->
        {:error, candidate_failure(:experiment_id, reason)}
    end
  end

  # The item row is locked before the link is read, so a concurrent duplicate
  # waits and then reads the committed link instead of creating a second
  # runtime record. A rollback discards the created record together with the
  # link, so one transaction never leaves an unlinked domain record.
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
         %OptimizationRun{} = candidate,
         _request
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
         _candidate,
         request
       ) do
    case Repo.get(OptimizationRun, run_id) do
      %OptimizationRun{} = run ->
        verify_link(RunIdentity.check(run, request), :optimization_run_id, run)

      nil ->
        Repo.rollback(
          {:error, StudyError.runtime_record_unavailable(:optimization_run_id, :not_found)}
        )
    end
  end

  defp reserve_experiment_locked(
         %StudyCollectionItem{experiment_id: nil} = item,
         %Experiment{} = candidate,
         _request
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
         _candidate,
         request
       ) do
    case Experiments.get(experiment_id) do
      %Experiment{} = experiment ->
        verify_link(ExperimentIdentity.check(experiment, request), :experiment_id, experiment)

      nil ->
        Repo.rollback({:error, StudyError.runtime_record_unavailable(:experiment_id, :not_found)})
    end
  end

  # A linked record answers the request, or the reservation fails and keeps the
  # link. The record itself stays unchanged in both cases.
  defp verify_link(:ok, _field, record), do: {:ok, record}

  defp verify_link({:error, :request_mismatch}, field, _record),
    do: Repo.rollback({:error, StudyError.runtime_record_mismatch(field)})

  defp link(item, attrs) do
    case item |> StudyCollectionItem.link_changeset(attrs) |> Repo.update() do
      {:ok, %StudyCollectionItem{}} -> :ok
      {:error, _changeset} -> Repo.rollback({:error, StudyError.collection_item_storage_failed()})
    end
  end
end
