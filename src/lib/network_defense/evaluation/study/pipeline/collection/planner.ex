defmodule NetworkDefense.Evaluation.Study.Pipeline.Collection.Planner do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.{Comparison, Graph, Strategy}

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Limits
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Phase
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.WorkItem
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Selection
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}

  # Collection work planning.
  #
  # One declared definition becomes stable positional work items. The planner
  # reads no runtime record and starts no optimization or simulation, so a
  # repeated call returns the same positions.

  @spec build_collection_work(StudyExecution.t(), StudyPhase.t(), Definition.t(), integer()) ::
          {:ok, [WorkItem.t()]} | {:error, StudyError.t()}
  def build_collection_work(
        %StudyExecution{} = execution,
        %StudyPhase{} = phase,
        %Definition{} = definition,
        replica_position
      ) do
    with :ok <- Phase.ensure_supported(phase),
         :ok <- Phase.ensure_belongs_to(execution, phase),
         :ok <- validate_replica(phase, replica_position),
         {:ok, limits} <- Limits.fetch(),
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

  @spec filter_tier([WorkItem.t()], Definition.t(), String.t()) ::
          {:ok, [WorkItem.t()]} | {:error, StudyError.t()}
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

    with {:ok, selection} <- Selection.from_execution(execution) do
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

  defp within_phase_item_cap(plan, %Limits{max_phase_items: limit}) do
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
      case WorkItem.new(Map.put(attrs, :item_position, item_position)) do
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
end
