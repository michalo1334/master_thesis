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

  Pilot evidence preserves plan order and shared attack-seed columns.
  """

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Collection.WorkItem
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Definition.{Graph, Strategy, TierRoot}
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Evidence
  alias NetworkDefense.Evaluation2.Study.Evidence.Comparison, as: ComparisonEvidence
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: CollectionStore
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefense.Evaluation2.Study.Views
  alias NetworkDefense.Graph.Graph, as: OutputGraph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.{OptimizationRun, OptimizationRuns}
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Simulation.{Experiment, Experiments, MissionImpact, Run, Seed}
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
  Assemble the Pilot snapshot in declared comparison and plan order.

  Each comparison shares one attack-seed column list across both sides.
  Missing or inconsistent observations return a bounded evidence error.
  """
  @spec assemble_evidence(Ecto.UUID.t()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, Error.t()}
  def assemble_evidence(study_phase_id) do
    with {:ok, context} <- stored(Persistence.fetch_phase_context(study_phase_id)),
         :ok <- pilot_phase(context.phase),
         {:ok, phase_run} <- stored(Persistence.fetch_phase_run(study_phase_id, :single)),
         {:ok, plan} <- stored(CollectionStore.fetch_collection_plan(phase_run.id)),
         {:ok, items} <- stored(CollectionStore.list_replica_items(phase_run.id, 0)),
         {:ok, observations} <- item_observations(plan.items, items),
         {:ok, evidence} <- build_evidence(observations, context.revision.definition) do
      stored(Persistence.insert_evidence_snapshot(study_phase_id, evidence))
    end
  end

  defp pilot_phase(%{phase: :pilot_collection}), do: :ok
  defp pilot_phase(_phase), do: {:error, incomplete_collection_evidence()}

  defp item_observations(work, items) do
    positions = Enum.to_list(0..(length(work) - 1)//1)

    if work != [] and Enum.map(items, & &1.item_position) == positions do
      work
      |> Enum.zip(items)
      |> Enum.reduce_while({:ok, []}, &collect_observation/2)
      |> reverse_observations()
    else
      {:error, incomplete_collection_evidence()}
    end
  end

  defp collect_observation({request, item}, {:ok, observations}) do
    case item_observation(request, item) do
      {:ok, observation} -> {:cont, {:ok, [observation | observations]}}
      :error -> {:halt, {:error, incomplete_collection_evidence()}}
    end
  end

  defp reverse_observations({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_observations({:error, error}), do: {:error, error}

  defp item_observation(%WorkItem{} = work, %CollectionItem{} = item) do
    with {:ok, optimization} <- evidence_optimization(item.optimization_run_id),
         {:ok, graph} <- evidence_graph(optimization.output_graph_revision_id),
         {:ok, experiment} <- evidence_experiment(item.experiment_id, optimization, work),
         {:ok, runs} <- evidence_runs(experiment) do
      impacts = Enum.map(runs, &mission_impact(graph, &1))

      if Enum.all?(impacts, &is_float/1) do
        {:ok, %{work: work, seeds: Enum.map(runs, & &1.seed), impacts: impacts}}
      else
        :error
      end
    end
  end

  defp evidence_optimization(id) when is_binary(id) do
    case OptimizationRuns.load(id) do
      %OptimizationRun{id: ^id, status: "completed", output_graph_revision_id: revision} = run ->
        case canonical_uuid(revision) do
          {:ok, _} -> {:ok, run}
          {:error, _} -> :error
        end

      _ ->
        :error
    end
  end

  defp evidence_optimization(_id), do: :error

  defp evidence_graph(revision) do
    case Graphs.load_revision(revision) do
      %OutputGraph{} = graph -> {:ok, graph}
      _ -> :error
    end
  end

  defp evidence_experiment(id, optimization, work) when is_binary(id) do
    case Experiments.load(id) do
      %Experiment{id: ^id, runs: runs} = experiment when is_list(runs) ->
        if experiment_matches?(experiment, optimization, work) do
          {:ok, experiment}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp evidence_experiment(_id, _optimization, _work), do: :error

  defp experiment_matches?(experiment, optimization, work) do
    experiment.status == :completed and
      experiment.graph_revision_id == optimization.output_graph_revision_id and
      experiment.master_seed == work.evaluation_root and
      experiment.initial_foothold_node_id == work.initial_foothold_node_id and
      valid_trial_count?(experiment, work)
  end

  defp valid_trial_count?(experiment, work) do
    is_integer(experiment.total_trials) and experiment.total_trials > 0 and
      experiment.total_trials == work.attack_count and
      experiment.completed_trials == experiment.total_trials
  end

  defp evidence_runs(%Experiment{} = experiment) do
    runs = Enum.sort_by(experiment.runs, & &1.trial_index)

    # Column identity follows the experiment seed and the trial index.
    if Enum.map(runs, & &1.trial_index) == Enum.to_list(1..experiment.total_trials) and
         Enum.all?(runs, fn run ->
           run.experiment_id == experiment.id and
             run.graph_revision_id == experiment.graph_revision_id and
             run.seed == Seed.child_seed(experiment.master_seed, run.trial_index)
         end) do
      {:ok, runs}
    else
      :error
    end
  end

  defp mission_impact(graph, run) do
    run
    |> Run.current_attacker_state()
    |> AttackerState.foothold_nodes()
    |> then(&MissionImpact.final(graph, &1))
  end

  defp build_evidence(observations, %Definition{family: family}) do
    count = length(family.comparisons)
    positions = Enum.to_list(0..(count - 1)//1)

    if count > 0 and Enum.all?(observations, &(&1.work.comparison_position in positions)) do
      positions
      |> Enum.reduce_while({:ok, []}, &collect_comparison(&1, &2, observations))
      |> reverse_observations()
      |> case do
        {:ok, comparisons} -> {:ok, %Evidence{comparisons: comparisons}}
        error -> error
      end
    else
      {:error, incomplete_collection_evidence()}
    end
  end

  defp collect_comparison(position, {:ok, comparisons}, observations) do
    case comparison_evidence(observations, position) do
      {:ok, comparison} -> {:cont, {:ok, [comparison | comparisons]}}
      :error -> {:halt, {:error, incomplete_collection_evidence()}}
    end
  end

  defp comparison_evidence(observations, position) do
    rows = Enum.filter(observations, &(&1.work.comparison_position == position))
    alternative = Enum.filter(rows, &(&1.work.side == :alternative))
    reference = Enum.filter(rows, &(&1.work.side == :reference))

    case rows do
      [%{seeds: seeds} | _] when alternative != [] and reference != [] ->
        if Enum.all?(rows, &(&1.seeds == seeds and length(&1.impacts) == length(seeds))) and
             length(alternative) + length(reference) == length(rows) do
          {:ok,
           %ComparisonEvidence{
             attack_seeds: seeds,
             alternative: Enum.map(alternative, & &1.impacts),
             reference: Enum.map(reference, & &1.impacts)
           }}
        else
          :error
        end

      _ ->
        :error
    end
  end

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

  defp incomplete_collection_evidence do
    %Error{
      category: :unavailable,
      issues: [
        %Error.Issue{
          code: "incomplete_collection_evidence",
          path: [],
          message: "The collection evidence is incomplete or inconsistent."
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
