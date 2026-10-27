defmodule NetworkDefense.Evaluation.Study.Collection do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.CollectionLimits
  alias NetworkDefense.Evaluation.Study.Contracts.CollectionResult
  alias NetworkDefense.Evaluation.Study.Contracts.CollectionWorkItem
  alias NetworkDefense.Evaluation.Study.Contracts.Definition

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.{Comparison, Graph, Strategy}

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.FinalSelection
  alias NetworkDefense.Evaluation.Study.Reservations
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

  @collection_phases [:pilot_collection, :final_collection]

  @spec build_collection_work(StudyExecution.t(), StudyPhase.t(), Definition.t(), integer()) ::
          {:ok, [CollectionWorkItem.t()]} | {:error, StudyError.t()}
  def build_collection_work(
        %StudyExecution{} = execution,
        %StudyPhase{} = phase,
        %Definition{} = definition,
        replica_position
      ) do
    with :ok <- ensure_supported_phase(phase),
         :ok <- validate_phase(execution, phase),
         :ok <- validate_replica(phase, replica_position),
         {:ok, limits} <- CollectionLimits.fetch(),
         {:ok, plan} <- plan(execution, phase, definition),
         :ok <- within_phase_item_cap(plan, limits) do
      items(plan, replica_position)
    end
  end

  @spec tier_order(Definition.t()) :: {:ok, [String.t()]} | {:error, StudyError.t()}
  def tier_order(%Definition{} = definition) do
    tiers = definition.family.comparisons |> Enum.map(& &1.tier) |> Enum.uniq()

    if tiers != [] and Enum.all?(tiers, &(is_binary(&1) and String.trim(&1) != "")),
      do: {:ok, tiers},
      else: {:error, StudyError.invalid_tier()}
  end

  @spec filter_tier([CollectionWorkItem.t()], Definition.t(), String.t()) ::
          {:ok, [CollectionWorkItem.t()]} | {:error, StudyError.t()}
  def filter_tier(items, definition, tier) do
    with {:ok, tiers} <- tier_order(definition), true <- tier in tiers do
      case Enum.filter(items, &(&1.comparison.tier == tier)) do
        [] -> {:error, StudyError.invalid_tier()}
        selected -> {:ok, selected}
      end
    else
      _ -> {:error, StudyError.invalid_tier()}
    end
  end

  @spec run_collection_item(Ecto.UUID.t()) ::
          {:ok, CollectionResult.t()} | {:error, StudyError.t()}
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
          {:ok, CollectionResult.t()} | {:error, StudyError.t()}
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
           build_collection_work(execution, phase, definition, item.replica_position) do
      case Enum.at(items, item.item_position) do
        %CollectionWorkItem{} = work_item ->
          {:ok, work_item}

        nil ->
          {:error, StudyError.invalid_collection_position(:item_position)}
      end
    end
  end

  defp item_context(collection_item_id) do
    with {:ok, item} <- load_item(collection_item_id),
         {:ok, phase} <- load_phase(item.study_phase_id),
         :ok <- ensure_supported_phase(phase),
         {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         :ok <- validate_phase(execution, phase),
         {:ok, work_item} <- canonical_work_item(execution, phase, definition, item),
         {:ok, limits} <- CollectionLimits.fetch(),
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

  defp ensure_supported_phase(%StudyPhase{phase: phase}) when phase in @collection_phases,
    do: :ok

  defp ensure_supported_phase(%StudyPhase{phase: phase}),
    do: {:error, StudyError.unsupported_collection_phase(phase)}

  defp validate_phase(%StudyExecution{id: execution_id}, %StudyPhase{} = phase) do
    if phase.execution_id == execution_id,
      do: :ok,
      else: {:error, StudyError.collection_phase_mismatch()}
  end

  defp validate_replica(%StudyPhase{phase: :pilot_collection}, 0), do: :ok

  defp validate_replica(%StudyPhase{phase: :final_collection}, position)
       when is_integer(position) and position in -1..4, do: :ok

  defp validate_replica(_, _),
    do: {:error, StudyError.invalid_collection_position(:replica_position)}

  defp plan(
         _execution,
         %StudyPhase{phase: :pilot_collection},
         %Definition{} = definition
       ) do
    collection = definition.pilot.collection

    collection_plan(
      definition,
      collection.roots,
      collection.selection_seeds,
      collection.plan_count_per_side,
      collection.attacks_per_plan,
      ["pilot", "collection"]
    )
  end

  defp plan(
         %StudyExecution{} = execution,
         %StudyPhase{phase: :final_collection},
         %Definition{} = definition
       ) do
    collection = definition.final.collection

    with {:ok, selection} <- FinalSelection.from_execution(execution) do
      collection_plan(
        definition,
        collection.roots,
        collection.selection_seeds,
        selection.plan_count_per_side,
        selection.attacks_per_plan,
        ["final", "collection"]
      )
    end
  end

  defp collection_plan(definition, roots, seeds, plan_count, attacks, path) do
    with {:ok, groups} <- groups(definition, roots, path),
         {:ok, selected_seeds} <- selection_seeds(seeds, plan_count, path) do
      {:ok,
       %{
         groups: groups,
         seeds: selected_seeds,
         attacks: attacks,
         iterations_per_run: definition.simulation.iterations_per_run,
         max_attempts: definition.simulation.max_attempts,
         definition_path: path
       }}
    end
  end

  defp groups(%Definition{} = definition, declared_roots, path) do
    roots = Map.new(declared_roots, &{&1.tier, &1.value})

    definition.family.comparisons
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {comparison, comparison_position}, {:ok, groups} ->
      case group(definition, comparison, comparison_position, roots, path) do
        {:ok, group} -> {:cont, {:ok, [group | groups]}}
        {:error, %StudyError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse_result()
  end

  defp group(
         %Definition{} = definition,
         %Comparison{} = comparison,
         comparison_position,
         roots,
         path
       ) do
    with {:ok, graph} <- graph(definition, comparison, comparison_position),
         {:ok, alternative} <-
           strategy(graph, comparison.alternative, comparison_position, "alternative"),
         {:ok, reference} <-
           strategy(graph, comparison.reference, comparison_position, "reference"),
         {:ok, root} <- root(roots, comparison, path) do
      {:ok,
       %{
         comparison: comparison,
         comparison_position: comparison_position,
         graph: graph,
         alternative: alternative,
         reference: reference,
         evaluation_root: root
       }}
    end
  end

  defp graph(%Definition{} = definition, %Comparison{} = comparison, comparison_position) do
    case Enum.find(definition.graphs, &(&1.tier == comparison.tier)) do
      %Graph{} = graph ->
        {:ok, graph}

      nil ->
        {:error, StudyError.incomplete_collection_definition(["graphs", comparison_position])}
    end
  end

  defp strategy(%Graph{} = graph, key, comparison_position, side) do
    case Enum.find(graph.strategies, &(&1.key == key)) do
      nil ->
        {:error,
         StudyError.incomplete_collection_definition([
           "family",
           "comparisons",
           comparison_position,
           side
         ])}

      strategy ->
        {:ok, strategy}
    end
  end

  defp root(roots, %Comparison{} = comparison, path) do
    case Map.fetch(roots, comparison.tier) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error, StudyError.incomplete_collection_definition(path ++ ["roots"])}
    end
  end

  defp selection_seeds(seeds, plan_count, path) do
    if length(seeds) >= plan_count do
      {:ok, Enum.take(seeds, plan_count)}
    else
      {:error, StudyError.incomplete_collection_definition(path ++ ["selection_seeds"])}
    end
  end

  defp within_phase_item_cap(plan, %CollectionLimits{max_phase_items: limit}) do
    actual = length(plan.groups) * 2 * length(plan.seeds)

    if actual <= limit,
      do: :ok,
      else: {:error, StudyError.collection_work_exceeds_limit(limit, actual)}
  end

  defp items(plan, replica_position) do
    plan.groups
    |> Enum.flat_map(fn group ->
      for {side, strategy} <- sides(group),
          {seed, plan_position} <- Enum.with_index(plan.seeds) do
        attrs(plan, group, side, strategy, seed, plan_position, replica_position)
      end
    end)
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {attrs, item_position}, {:ok, items} ->
      case CollectionWorkItem.new(Map.put(attrs, :item_position, item_position)) do
        {:ok, item} ->
          {:cont, {:ok, [item | items]}}

        :error ->
          {:halt, {:error, StudyError.incomplete_collection_definition(plan.definition_path)}}
      end
    end)
    |> reverse_result()
  end

  defp sides(group), do: [{:alternative, group.alternative}, {:reference, group.reference}]

  defp attrs(plan, group, side, strategy, seed, plan_position, replica_position) do
    %{
      replica_position: replica_position,
      comparison_position: group.comparison_position,
      comparison: Comparison.to_params(group.comparison),
      side: side,
      graph_revision_id: group.graph.graph_revision_id,
      initial_foothold_node_id: group.graph.initial_foothold_node_id,
      strategy: Strategy.to_params(strategy),
      budget: group.comparison.budget,
      plan_position: plan_position,
      selection_seed: seed,
      evaluation_root: group.evaluation_root,
      attack_count: plan.attacks,
      iterations_per_run: plan.iterations_per_run,
      max_attempts: plan.max_attempts
    }
  end

  defp reverse_result({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_result({:error, %StudyError{} = error}), do: {:error, error}

  defp within_item_cap(%CollectionWorkItem{item_position: item_position}, %CollectionLimits{
         max_phase_items: limit
       }) do
    if item_position < limit,
      do: :ok,
      else: {:error, StudyError.collection_work_exceeds_limit(limit, item_position + 1)}
  end

  defp run_optimization(%StudyCollectionItem{} = item, %CollectionWorkItem{} = work_item) do
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
         %CollectionWorkItem{} = work_item,
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

  defp optimization_request(%StudyCollectionItem{} = item, %CollectionWorkItem{} = work_item) do
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

  defp foothold(%CollectionWorkItem{} = work_item) do
    if OptimizationParams.requires_initial_foothold?(work_item.strategy.key),
      do: work_item.initial_foothold_node_id
  end

  defp scoring_settings(%CollectionWorkItem{strategy: %{scoring: nil}}), do: nil

  defp scoring_settings(%CollectionWorkItem{} = work_item) do
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
         %CollectionWorkItem{} = work_item,
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
    case CollectionResult.new(%{
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
