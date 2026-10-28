defmodule NetworkDefense.Evaluation.Study.Pipeline.Collection.Runner do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{
    Limits,
    Phase,
    Planner,
    Receipt,
    Reservations,
    WorkItem
  }

  alias NetworkDefense.Evaluation.Study.Revisions
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyPhase}

  alias NetworkDefense.Optimization.Contracts.{
    OptimizationParams,
    RunOptimizationRequest,
    SimulationSettings
  }

  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Contracts.{RunSimulationRequest, SimulationParams}
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulations

  # Runs one persisted collection item.
  #
  # The runner reads the stored row, recomputes its canonical work item, and
  # performs the reservation, optimization, and simulation calls. A repeated
  # call reuses the stored reservation and the completed records.

  @spec run_collection_item(Ecto.UUID.t()) ::
          {:ok, Receipt.t()} | {:error, StudyError.t()}
  def run_collection_item(collection_item_id) do
    with {:ok, _item} <- run_plan_selection_item(collection_item_id) do
      run_simulation_item(collection_item_id)
    end
  end

  @spec run_plan_selection_item(Ecto.UUID.t()) ::
          {:ok, StudyCollectionItem.t()} | {:error, StudyError.t()}
  def run_plan_selection_item(collection_item_id) do
    with {:ok, item, _phase, _execution, _definition, work_item} <-
           item_context(collection_item_id),
         {:ok, _run} <- run_optimization(item, work_item),
         %StudyCollectionItem{} = reloaded <- Repo.get(StudyCollectionItem, item.id) do
      {:ok, reloaded}
    else
      nil -> {:error, StudyError.collection_item_not_found()}
      {:error, %StudyError{} = error} -> {:error, error}
    end
  end

  @spec run_simulation_item(Ecto.UUID.t()) ::
          {:ok, Receipt.t()} | {:error, StudyError.t()}
  def run_simulation_item(collection_item_id) do
    with {:ok, item, _phase, _execution, definition, work_item} <-
           item_context(collection_item_id),
         {:ok, run} <- linked_completed_optimization(item),
         {:ok, experiment} <- run_experiment(item, work_item, definition, run) do
      result(item, run, experiment)
    end
  end

  # The item identifier arrives in the task payload, so malformed input becomes a
  # bounded error here. The phase and execution identifiers come from a stored
  # row and are already typed, so they are read directly.
  defp load_item(collection_item_id) do
    with {:ok, id} <- cast_id(collection_item_id) do
      case Repo.get(StudyCollectionItem, id) do
        %StudyCollectionItem{} = item -> {:ok, item}
        nil -> {:error, StudyError.collection_item_not_found()}
      end
    end
  end

  defp cast_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, StudyError.collection_item_not_found()}
    end
  end

  defp load_phase(study_phase_id) do
    case Repo.get(StudyPhase, study_phase_id) do
      %StudyPhase{} = phase -> {:ok, phase}
      nil -> {:error, StudyError.invalid_study_phase()}
    end
  end

  defp load_execution(execution_id) do
    case Repo.get(StudyExecution, execution_id) do
      %StudyExecution{} = execution -> {:ok, execution}
      nil -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp canonical_work_item(execution, phase, definition, %StudyCollectionItem{} = item) do
    with {:ok, items} <-
           Planner.build_collection_work(execution, phase, definition, item.replica_position) do
      case Enum.at(items, item.item_position) do
        %WorkItem{} = work_item ->
          {:ok, work_item}

        nil ->
          {:error, StudyError.invalid_collection_position(:item_position)}
      end
    end
  end

  defp item_context(collection_item_id) do
    with {:ok, item} <- load_item(collection_item_id),
         {:ok, phase} <- load_phase(item.study_phase_id),
         :ok <- Phase.ensure_supported(phase),
         {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         :ok <- Phase.ensure_belongs_to(execution, phase),
         {:ok, work_item} <- canonical_work_item(execution, phase, definition, item),
         {:ok, limits} <- Limits.fetch(),
         :ok <- within_item_cap(work_item, limits) do
      {:ok, item, phase, execution, definition, work_item}
    end
  end

  defp linked_completed_optimization(%StudyCollectionItem{optimization_run_id: run_id})
       when is_binary(run_id) do
    case Repo.get(OptimizationRun, run_id) do
      %OptimizationRun{status: "completed", output_graph_revision_id: output} = run
      when is_binary(output) and output != "" ->
        {:ok, run}

      %OptimizationRun{} ->
        {:error, StudyError.runtime_execution_failed(:optimization_run_id, :incomplete)}

      nil ->
        {:error, StudyError.runtime_record_unavailable(:optimization_run_id, :not_found)}
    end
  end

  defp linked_completed_optimization(%StudyCollectionItem{}),
    do: {:error, StudyError.runtime_record_unavailable(:optimization_run_id, :not_found)}

  defp within_item_cap(%WorkItem{item_position: item_position}, %Limits{
         max_phase_items: limit
       }) do
    if item_position < limit,
      do: :ok,
      else: {:error, StudyError.collection_work_exceeds_limit(limit, item_position + 1)}
  end

  defp run_optimization(%StudyCollectionItem{} = item, %WorkItem{} = work_item) do
    request = optimization_request(item, work_item)

    with {:ok, %OptimizationRun{} = reserved} <-
           Reservations.reserve_optimization(item.id, request) do
      case Optimizations.run_reserved(reserved.id,
             correlation_id: request.correlation_id
           ) do
        {:ok,
         %OptimizationRun{
           status: "completed",
           output_graph_revision_id: output_graph_revision_id
         } = run}
        when is_binary(output_graph_revision_id) and output_graph_revision_id != "" ->
          {:ok, run}

        {:ok, %OptimizationRun{}} ->
          {:error, StudyError.runtime_execution_failed(:optimization_run_id, :incomplete)}

        {:error, reason} ->
          {:error, StudyError.runtime_execution_failed(:optimization_run_id, reason)}
      end
    end
  end

  defp run_experiment(
         %StudyCollectionItem{} = item,
         %WorkItem{} = work_item,
         %Definition{} = definition,
         %OptimizationRun{} = run
       ) do
    with :ok <- ensure_output_graph(run),
         request <- simulation_request(item, work_item, definition, run),
         {:ok, %Experiment{} = reserved} <- Reservations.reserve_experiment(item.id, request) do
      simulation_result(reserved, item)
    end
  end

  defp ensure_output_graph(%OptimizationRun{output_graph_revision_id: output})
       when is_binary(output) and output != "",
       do: :ok

  defp ensure_output_graph(_run),
    do: {:error, StudyError.runtime_execution_failed(:optimization_run_id, :incomplete)}

  defp simulation_result(%Experiment{} = reserved, %StudyCollectionItem{} = item) do
    case Simulations.run(reserved.id, correlation_id: correlation_id(item, :experiment)) do
      {:ok,
       %Experiment{status: :completed, completed_trials: completed, total_trials: total} =
           experiment}
      when is_integer(completed) and is_integer(total) and total > 0 and completed == total ->
        {:ok, experiment}

      {:ok, %Experiment{} = experiment} ->
        {:error, StudyError.runtime_execution_failed(:experiment_id, experiment.status)}

      {:error, reason} ->
        {:error, StudyError.runtime_execution_failed(:experiment_id, reason)}
    end
  end

  defp optimization_request(%StudyCollectionItem{} = item, %WorkItem{} = work_item) do
    %RunOptimizationRequest{
      graph_revision_id: work_item.graph_revision_id,
      correlation_id: correlation_id(item, :optimization),
      optimization_params: %OptimizationParams{
        strategy: work_item.strategy.key,
        budget: work_item.budget,
        seed: work_item.selection_seed,
        candidate_action_types: work_item.strategy.candidate_action_types,
        require_pre_attack_feasibility: work_item.strategy.require_pre_attack_feasibility,
        initial_foothold_node_id: foothold(work_item),
        simulation_params: scoring_settings(work_item)
      }
    }
  end

  defp foothold(%WorkItem{} = work_item) do
    if OptimizationParams.requires_initial_foothold?(work_item.strategy.key),
      do: work_item.initial_foothold_node_id
  end

  defp scoring_settings(%WorkItem{strategy: %{scoring: nil}}), do: nil

  defp scoring_settings(%WorkItem{} = work_item) do
    scoring = work_item.strategy.scoring

    %SimulationSettings{
      objective: scoring.objective,
      monte_carlo_trials: scoring.monte_carlo_trials,
      iterations_per_run: scoring.iterations_per_run,
      max_attempts: scoring.max_attempts,
      rules: scoring.rules
    }
  end

  defp simulation_request(
         %StudyCollectionItem{} = item,
         %WorkItem{} = work_item,
         %Definition{} = definition,
         %OptimizationRun{} = run
       ) do
    %RunSimulationRequest{
      graph_revision_id: run.output_graph_revision_id,
      correlation_id: correlation_id(item, :experiment),
      simulation_params: %SimulationParams{
        monte_carlo_trials: work_item.attack_count,
        iterations_per_run: work_item.iterations_per_run,
        initial_foothold_node_id: work_item.initial_foothold_node_id,
        seed: work_item.evaluation_root,
        generate_seed: false,
        max_attempts: work_item.max_attempts,
        rules: definition.simulation.rules,
        require_pre_attack_feasibility: definition.simulation.require_pre_attack_feasibility
      }
    }
  end

  defp result(%StudyCollectionItem{} = item, %OptimizationRun{} = run, %Experiment{} = experiment) do
    case Receipt.new(%{
           collection_item_id: item.id,
           replica_position: item.replica_position,
           item_position: item.item_position,
           optimization_run_id: run.id,
           experiment_id: experiment.id,
           completed_trials: experiment.completed_trials,
           total_trials: experiment.total_trials
         }) do
      {:ok, result} -> {:ok, result}
      :error -> {:error, StudyError.collection_result_invalid()}
    end
  end

  defp correlation_id(%StudyCollectionItem{id: id}, step), do: "#{id}/#{step}"
end
