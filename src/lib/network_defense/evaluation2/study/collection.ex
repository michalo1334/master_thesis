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

  The plan follows tier order, declared budget order, CVSS then alternatives,
  and logical row order. Comparisons share the collected CVSS group. Planning
  the same definition twice produces equal work; a phase run keeps its plan.

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
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Evidence
  alias NetworkDefense.Evaluation2.Study.Evidence.Comparison, as: ComparisonEvidence
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: CollectionStore
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Evaluation2.Study.Persistence.EvidenceSnapshot
  alias NetworkDefense.Evaluation2.Study.Randomness
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefense.Evaluation2.Study.Views
  alias NetworkDefense.Graph.Graph, as: OutputGraph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.{OptimizationRun, OptimizationRuns, RunIdentity}
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Simulation.{Experiment, Experiments, MissionImpact, Run, Seed}
  alias NetworkDefense.Simulations

  @doc """
  Build or load the Pilot plan of one collection phase run.

  The plan collects each tier/budget/strategy group once per logical row.
  Resolved requests freeze shared policy, simulation settings, and scalar seeds.
  An equal retry returns the stored plan. A different payload returns a conflict
  and preserves that plan. Revision creation establishes the definition invariants.
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
         true <- optimization_matches?(optimization, work),
         {:ok, graph} <- evidence_graph(optimization.output_graph_revision_id),
         {:ok, experiment} <- evidence_experiment(item.experiment_id, optimization, work),
         {:ok, runs} <- evidence_runs(experiment) do
      impacts = Enum.map(runs, &mission_impact(graph, &1))

      if Enum.all?(
           impacts,
           &(Definition.finite?(&1) and &1 >= work.mission_impact_bound.minimum and
               &1 <= work.mission_impact_bound.maximum)
         ) do
        {:ok, %{work: work, seeds: Enum.map(runs, & &1.seed), impacts: impacts}}
      else
        :error
      end
    else
      _ -> :error
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

  defp optimization_matches?(run, work) do
    request = WorkItem.optimization_request(work, "evidence")
    expected = RunIdentity.execution_config(request)

    run.graph_revision_id == work.graph_revision and run.strategy == work.strategy.key and
      run.requested_budget == work.budget and run.seed == work.selection_seed and
      run.execution_config == expected
  end

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
      experiment.iteration_count == work.simulation.iterations_per_run and
      experiment.max_attempts == work.simulation.max_attempts and
      experiment.rules == work.simulation.rules and
      experiment.require_pre_attack_feasibility == work.require_pre_attack_feasibility and
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

  defp build_evidence(observations, %Definition{} = definition) do
    comparisons = Definition.comparisons(definition)
    groups = Definition.collection_groups(definition)
    capacity = Definition.pilot_capacity(definition)
    expected = for group <- groups, row <- 0..(capacity.plans - 1), do: {group.position, row}
    actual = Enum.map(observations, &{&1.work.group_position, &1.work.plan_position})

    if actual == expected do
      comparisons
      |> Enum.reduce_while({:ok, []}, &collect_comparison(&1, &2, observations))
      |> reverse_observations()
      |> case do
        {:ok, values} -> {:ok, %Evidence{comparisons: values}}
        error -> error
      end
    else
      {:error, incomplete_collection_evidence()}
    end
  end

  defp collect_comparison(comparison, {:ok, result}, observations) do
    case comparison_evidence(observations, comparison) do
      {:ok, value} -> {:cont, {:ok, [value | result]}}
      :error -> {:halt, {:error, incomplete_collection_evidence()}}
    end
  end

  defp comparison_evidence(observations, comparison) do
    alternative =
      Enum.filter(observations, &(&1.work.group_position == comparison.group_position))

    reference =
      Enum.filter(observations, &(&1.work.group_position == comparison.reference_group_position))

    rows = alternative ++ reference

    case rows do
      [%{seeds: seeds} | _] when alternative != [] and reference != [] ->
        if Enum.all?(rows, &(&1.seeds == seeds and length(&1.impacts) == length(seeds))) do
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
    capacity = Definition.pilot_capacity(definition)

    items =
      for group <- Definition.collection_groups(definition),
          row <- 0..(capacity.plans - 1) do
        graph = Enum.find(definition.tiers, &(&1.tier == group.tier))

        %WorkItem{
          group_position: group.position,
          plan_position: row,
          graph_revision: graph.graph_revision_id,
          initial_foothold_node_id: graph.initial_foothold_node_id,
          strategy: group.strategy,
          budget: group.budget,
          candidate_action_types:
            Definition.effective_action_types(definition, group.strategy.key),
          require_pre_attack_feasibility: Definition.require_feasibility?(definition),
          simulation: definition.simulation,
          mission_impact_bound: graph.mission_impact_bound,
          selection_seed: Randomness.selection_seed(definition, :pilot, row),
          evaluation_root: Randomness.evaluation_root(definition, :pilot, group.tier),
          attack_count: capacity.attacks
        }
      end

    {:ok, items}
  end

  defp canonical_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, ^value} -> {:ok, value}
      _ -> {:error, invalid_collection_definition()}
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
