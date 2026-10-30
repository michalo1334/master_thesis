defmodule NetworkDefense.Evaluation2.Study.Collection do
  @moduledoc """
  Collection work of the Pilot and Final phases.

  A collection phase run owns one immutable plan, and the plan holds the complete
  ordered list of resolved `WorkItem` requests. Every replica of that run reuses
  the plan, and each item row owns the two effect links. Stored rows and their
  transactions belong to `Study.Persistence.Collection`. The optimization and
  simulation domains own the effects themselves.

  ```mermaid
  flowchart LR
      P[collection plan] --> I[replica items]
      I --> O[optimization run]
      O --> S[simulation experiment]
      S --> E[evidence snapshot]
  ```

  The plan order is the declared comparison order, then the alternative side
  before the reference side, then the first planned selection seeds in declared
  order. Planning the same definition twice produces equal work, and the same
  phase run keeps its stored plan.

  Mapped Gust tasks call `run_optimization/1` and `run_simulation/1`. Gust owns
  batch execution, dependency fan-in, and retry, so this module holds no
  scheduler, batch runner, or retry loop. A retried task reuses the effect links
  of its item, so one item never creates a second run or a second experiment.

  Evidence assembly stays unavailable until the evidence slice exists.
  """

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Collection.WorkItem
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Definition.{Graph, Strategy, TierRoot}
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: CollectionStore
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefense.Evaluation2.Study.Views
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulations

  @doc """
  Build or load the Pilot plan of one collection phase run.

  The plan covers every declared comparison, both sides of each comparison, and
  the first `plan_count_per_side` selection seeds in declared order. The resolved
  strategy owns the optimization budget. A repeated call with the same definition
  returns the stored plan, and a different payload keeps the stored plan and
  returns a conflict error.

  A definition that cannot produce one complete work item returns
  `invalid_collection_definition`. Full definition validation belongs to revision
  creation.
  """
  @spec prepare_pilot(Ecto.UUID.t(), Definition.t()) ::
          {:ok, CollectionPlan.t()} | {:error, Error.t()}
  def prepare_pilot(phase_run_id, %Definition{} = definition) do
    with {:ok, work_items} <- pilot_work(definition) do
      stored(CollectionStore.insert_collection_plan(phase_run_id, work_items))
    end
  end

  @doc """
  Construct or load the Final plan of one tier collection phase run.

  Final collection is not part of the current slice, so every call returns the
  bounded `not_implemented` error.
  """
  @spec prepare_final(Ecto.UUID.t(), Definition.t(), Selection.t(), Tier.t()) ::
          {:ok, CollectionPlan.t()} | {:error, Error.t()}
  def prepare_final(_phase_run_id, _definition, _selection, _tier),
    do: {:error, Placeholder.error(:prepare_final)}

  @doc """
  Create or load the complete ordered item batch of one replica.

  `Study.Persistence.Collection` creates one item row per plan position, so a
  caller cannot create a partial replica. Pilot uses replica position `0`. Final
  uses warm-up `-1` and the measured replicas `0..4`. A repeated call returns the
  same ordered rows.
  """
  @spec prepare_replica(Ecto.UUID.t(), CollectionItem.replica_position()) ::
          {:ok, [CollectionItem.t()]} | {:error, Error.t()}
  def prepare_replica(plan_id, replica_position) do
    stored(CollectionStore.prepare_collection_items(plan_id, replica_position))
  end

  @doc """
  Run the optimization effect of one collection item.

  The reservation creates or reuses the run linked to the item and derives the
  request from the immutable plan, so a retried task keeps one run. The call
  returns `:ok` when the returned run is the reserved run, its status is
  `"completed"`, and its output graph revision is a canonical UUID.
  """
  @spec run_optimization(Ecto.UUID.t()) :: :ok | {:error, Error.t()}
  def run_optimization(item_id) do
    with {:ok, %OptimizationRun{} = reserved} <-
           stored(CollectionStore.reserve_optimization(item_id)),
         {:ok, %OptimizationRun{} = run} <- optimization_effect(reserved, item_id) do
      completed_optimization(reserved, run)
    end
  end

  @doc """
  Run the simulation effect of one collection item.

  The reservation consumes the optimization run already linked to the item, so
  the simulation request needs no caller input. The call returns `:ok` when the
  returned experiment is the reserved experiment, its status is `:completed`, it
  reports trials, and every trial completed.
  """
  @spec run_simulation(Ecto.UUID.t()) :: :ok | {:error, Error.t()}
  def run_simulation(item_id) do
    with {:ok, %Experiment{} = reserved} <- stored(CollectionStore.reserve_experiment(item_id)),
         {:ok, %Experiment{} = experiment} <- simulation_effect(reserved, item_id) do
      completed_experiment(reserved, experiment)
    end
  end

  @doc """
  Assemble or load the evidence snapshot of one collection phase.

  Evidence assembly is unavailable until the evidence slice exists, so every call
  returns the bounded `not_implemented` error.
  """
  @spec assemble_evidence(Ecto.UUID.t()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, Error.t()}
  def assemble_evidence(_study_phase_id),
    do: {:error, Placeholder.error(:assemble_evidence)}

  # --- planning ------------------------------------------------------------

  defp pilot_work(%Definition{} = definition) do
    collection = definition.pilot.collection

    with :ok <- positive_count(collection.plan_count_per_side),
         :ok <- positive_count(collection.attacks_per_plan),
         {:ok, seeds} <- pilot_seeds(collection.selection_seeds, collection.plan_count_per_side) do
      comparison_work(definition, collection, seeds)
    end
  end

  defp comparison_work(%Definition{} = definition, collection, seeds) do
    definition.family.comparisons
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {comparison, position}, {:ok, groups} ->
      case comparison_group(definition, collection, comparison, position, seeds) do
        {:ok, work_items} -> {:cont, {:ok, [work_items | groups]}}
        {:error, failure} -> {:halt, {:error, failure}}
      end
    end)
    |> ordered_work()
  end

  defp comparison_group(definition, collection, comparison, position, seeds) do
    with {:ok, graph} <- tier_graph(definition.graphs, comparison.tier),
         {:ok, alternative} <- graph_strategy(graph, comparison.alternative),
         {:ok, reference} <- graph_strategy(graph, comparison.reference),
         {:ok, root} <- pilot_root(collection.roots, comparison.tier),
         {:ok, revision} <- canonical_uuid(graph.graph_revision_id),
         {:ok, foothold} <- canonical_uuid(graph.initial_foothold_node_id) do
      resolved = %{
        comparison_position: position,
        graph_revision: revision,
        foothold: foothold,
        seeds: seeds,
        evaluation_root: root,
        attack_count: collection.attacks_per_plan
      }

      {:ok, sides(alternative, reference) |> Enum.flat_map(&side_work(&1, resolved))}
    end
  end

  defp sides(alternative, reference),
    do: [{:alternative, alternative}, {:reference, reference}]

  defp side_work({side, strategy}, resolved) do
    Enum.map(resolved.seeds, fn seed ->
      %WorkItem{
        comparison_position: resolved.comparison_position,
        side: side,
        graph_revision: resolved.graph_revision,
        initial_foothold_node_id: resolved.foothold,
        strategy: strategy,
        selection_seed: seed,
        evaluation_root: resolved.evaluation_root,
        attack_count: resolved.attack_count
      }
    end)
  end

  defp ordered_work({:ok, groups}), do: {:ok, groups |> Enum.reverse() |> Enum.concat()}
  defp ordered_work({:error, failure}), do: {:error, failure}

  defp tier_graph(graphs, tier) do
    case Enum.find(graphs, &(&1.tier == tier)) do
      %Graph{} = graph -> {:ok, graph}
      nil -> {:error, invalid_collection_definition()}
    end
  end

  defp graph_strategy(%Graph{strategies: strategies}, key) do
    case Enum.find(strategies, &(&1.key == key)) do
      %Strategy{} = strategy -> {:ok, strategy}
      nil -> {:error, invalid_collection_definition()}
    end
  end

  defp pilot_root(roots, tier) do
    case Enum.find(roots, &(&1.tier == tier)) do
      %TierRoot{value: value} -> {:ok, value}
      nil -> {:error, invalid_collection_definition()}
    end
  end

  defp pilot_seeds(seeds, count) when is_list(seeds) and count > 0 do
    if length(seeds) >= count do
      {:ok, Enum.take(seeds, count)}
    else
      {:error, invalid_collection_definition()}
    end
  end

  defp pilot_seeds(_seeds, _count), do: {:error, invalid_collection_definition()}

  defp positive_count(value) when is_integer(value) and value > 0, do: :ok
  defp positive_count(_value), do: {:error, invalid_collection_definition()}

  # The persisted request carries canonical identifiers only, so a decoded plan
  # names one stored graph revision and one stored node without extra parsing.
  defp canonical_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, ^value} -> {:ok, value}
      _not_canonical -> {:error, invalid_collection_definition()}
    end
  end

  defp canonical_uuid(_value), do: {:error, invalid_collection_definition()}

  # --- effect completion ---------------------------------------------------

  defp optimization_effect(%OptimizationRun{id: run_id}, item_id) do
    case Optimizations.run_reserved(run_id, correlation_id: "#{item_id}/optimization") do
      {:ok, %OptimizationRun{} = run} -> {:ok, run}
      {:error, _reason} -> {:error, collection_effect_failed()}
    end
  end

  defp completed_optimization(
         %OptimizationRun{id: id},
         %OptimizationRun{id: id, status: "completed", output_graph_revision_id: revision}
       ) do
    case canonical_uuid(revision) do
      {:ok, _revision} -> :ok
      {:error, _failure} -> {:error, incomplete_collection_effect()}
    end
  end

  defp completed_optimization(%OptimizationRun{}, %OptimizationRun{}),
    do: {:error, incomplete_collection_effect()}

  defp simulation_effect(%Experiment{id: experiment_id}, item_id) do
    case Simulations.run(experiment_id, correlation_id: "#{item_id}/experiment") do
      {:ok, %Experiment{} = experiment} -> {:ok, experiment}
      {:error, _reason} -> {:error, collection_effect_failed()}
    end
  end

  defp completed_experiment(
         %Experiment{id: id},
         %Experiment{
           id: id,
           status: :completed,
           total_trials: total_trials,
           completed_trials: completed_trials
         }
       )
       when is_integer(total_trials) and total_trials > 0 and completed_trials == total_trials,
       do: :ok

  defp completed_experiment(%Experiment{}, %Experiment{}),
    do: {:error, incomplete_collection_effect()}

  # --- bounded values ------------------------------------------------------

  # Every persistence failure crosses this capability in one bounded public
  # shape, and the internal cause stays inside persistence.
  defp stored({:ok, value}), do: {:ok, value}
  defp stored({:error, %Persistence.Error{} = failure}), do: {:error, Views.error(failure)}

  defp invalid_collection_definition do
    %Error{
      category: :unavailable,
      issues: [
        %Error.Issue{
          code: "invalid_collection_definition",
          path: [],
          message: "The collection definition cannot produce complete collection work."
        }
      ]
    }
  end

  defp incomplete_collection_effect do
    %Error{
      category: :unavailable,
      issues: [
        %Error.Issue{
          code: "incomplete_collection_effect",
          path: [],
          message: "The collection effect reported an incomplete result."
        }
      ]
    }
  end

  defp collection_effect_failed do
    %Error{
      category: :unavailable,
      issues: [
        %Error.Issue{
          code: "collection_effect_failed",
          path: [],
          message: "The collection effect did not finish."
        }
      ]
    }
  end
end
