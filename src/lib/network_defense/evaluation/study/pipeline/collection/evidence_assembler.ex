defmodule NetworkDefense.Evaluation.Study.Pipeline.Collection.EvidenceAssembler do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonSide, Evidence, PlanEvidence}

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Evidence.Contracts.{
    ComparisonEvidence,
    Provenance
  }

  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Comparison
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{Planner, RunIdentity, WorkItem}
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyPhase}
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, Experiments, MissionImpact, Run}

  # Rebuilds snapshot evidence from immutable stored rows.
  #
  # The assembler reads the stored collection items, their optimization and
  # experiment results, and the declared definition. It never writes. The
  # result is one evidence matrix per declared comparison, in declared order,
  # plus the raw item evidence that a payload builder needs.
  #
  # The caller owns the evidence error policy, because the same reconstruction
  # serves both stages:
  #
  #     EvidenceAssembler.assemble(phase, items, definition,
  #       replica_position: 0,
  #       incomplete: &StudyError.incomplete_pilot_evidence/1
  #     )
  #
  # Private helpers report an evidence gap as its path. The assembler turns that
  # path into the caller's error once, so no stage-specific error reaches shared
  # code.
  @default_replica_position 0

  @type item_evidence :: %{
          work: WorkItem.t(),
          optimization: OptimizationRun.t(),
          experiment: Experiment.t(),
          runs: [Run.t()],
          attack_seeds: [non_neg_integer()],
          mission_impacts: [float()]
        }

  @type context :: %{
          incomplete: (list() -> term()) | nil,
          replica_position: non_neg_integer()
        }

  @spec assemble(StudyPhase.t(), [StudyCollectionItem.t()], Definition.t(), keyword()) ::
          {:ok, {[ComparisonEvidence.t()], [item_evidence()]}} | {:error, term()}
  def assemble(phase, collection_items, definition, opts \\ [])

  def assemble(%StudyPhase{} = phase, collection_items, %Definition{} = definition, opts)
      when is_list(collection_items) and is_list(opts) do
    context = context(opts)

    case collect(phase, collection_items, definition, context.replica_position) do
      {:ok, result} -> {:ok, result}
      {:error, %StudyError{} = error} -> {:error, error}
      {:error, path} when is_list(path) -> fail(context, path)
    end
  end

  def assemble(_phase, _collection_items, _definition, opts),
    do: fail(context(opts), ["collection_items"])

  defp collect(phase, collection_items, definition, replica_position) do
    with {:ok, item_ids} <- collection_item_ids(collection_items),
         {:ok, execution} <- load_execution(phase.execution_id),
         {:ok, work} <-
           Planner.build_collection_work(execution, phase, definition, replica_position),
         {:ok, ordered} <- order_items(phase, work, item_ids, replica_position),
         {:ok, evidence} <- item_evidence(ordered),
         {:ok, comparisons} <- comparisons(evidence, definition) do
      {:ok, {comparisons, evidence}}
    end
  end

  defp context(opts) when is_list(opts) do
    %{
      incomplete: Keyword.get(opts, :incomplete),
      replica_position: Keyword.get(opts, :replica_position, @default_replica_position)
    }
  end

  defp context(_opts), do: %{incomplete: nil, replica_position: @default_replica_position}

  defp fail(%{incomplete: fun}, path) when is_function(fun, 1), do: {:error, fun.(path)}
  defp fail(_context, _path), do: {:error, :incomplete_evidence}

  # The stable item identity contract. A stage validates its supplied items with
  # the same rule the reconstruction uses.
  @doc false
  @spec collection_item_ids([StudyCollectionItem.t()]) ::
          {:ok, [Ecto.UUID.t()]} | {:error, list()}
  def collection_item_ids(collection_items) do
    collection_items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, ids} ->
      case collection_item_id(item) do
        {:ok, id} -> {:cont, {:ok, [id | ids]}}
        :error -> {:halt, {:error, ["collection_items"]}}
      end
    end)
    |> then(fn
      {:ok, ids} -> unique_ids(ids)
      error -> error
    end)
  end

  defp collection_item_id(%StudyCollectionItem{id: id}), do: cast_id(id)
  defp collection_item_id(_value), do: :error

  defp unique_ids(ids) do
    if length(Enum.uniq(ids)) == length(ids),
      do: {:ok, ids},
      else: {:error, ["collection_items"]}
  end

  defp load_execution(execution_id) do
    case cast_id(execution_id) do
      {:ok, id} ->
        case Repo.get(StudyExecution, id) do
          %StudyExecution{} = execution -> {:ok, execution}
          nil -> {:error, StudyError.invalid_study_phase()}
        end

      :error ->
        {:error, StudyError.invalid_study_phase()}
    end
  end

  # The declared order is authoritative: the supplied items must be exactly the
  # stored items of the replica, one per declared position.
  defp order_items(%StudyPhase{id: phase_id}, work, item_ids, replica_position) do
    expected = Enum.map(work, & &1.item_position)

    with {:ok, items} <- reload_items(item_ids),
         :ok <- exact_item_set?(phase_id, items, expected, replica_position) do
      by_position = Map.new(items, &{&1.item_position, &1})
      {:ok, Enum.map(work, &{&1, Map.fetch!(by_position, &1.item_position)})}
    end
  end

  defp reload_items(item_ids) do
    items = Repo.all(from item in StudyCollectionItem, where: item.id in ^item_ids)

    if length(items) == length(item_ids), do: {:ok, items}, else: {:error, ["collection_items"]}
  end

  defp exact_item_set?(phase_id, items, expected, replica_position) do
    stored =
      Repo.all(
        from item in StudyCollectionItem,
          where: item.study_phase_id == ^phase_id and item.replica_position == ^replica_position
      )

    stored_ids = stored |> Enum.map(& &1.id) |> Enum.sort()
    supplied_ids = items |> Enum.map(& &1.id) |> Enum.sort()
    stored_positions = stored |> Enum.map(& &1.item_position) |> Enum.sort()

    if stored_ids == supplied_ids and stored_positions == expected,
      do: :ok,
      else: {:error, ["collection_items"]}
  end

  defp item_evidence(ordered) do
    ordered
    |> Enum.reduce_while({:ok, []}, fn {work, item}, {:ok, collected} ->
      case load_item_evidence(work, item) do
        {:ok, evidence} -> {:cont, {:ok, [evidence | collected]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse()
  end

  @spec load_item_evidence(WorkItem.t(), StudyCollectionItem.t()) ::
          {:ok, item_evidence()} | {:error, list() | StudyError.t()}
  defp load_item_evidence(%WorkItem{} = work, %StudyCollectionItem{} = item) do
    with {:ok, optimization} <- optimization(item),
         :ok <- validate_optimization(optimization, work, item),
         {:ok, graph} <- output_graph(optimization, item),
         {:ok, experiment, runs} <- experiment(item),
         :ok <- validate_experiment(experiment, optimization, work, item),
         :ok <- validate_runs(runs, experiment, item) do
      {:ok,
       %{
         work: work,
         optimization: optimization,
         experiment: experiment,
         runs: runs,
         attack_seeds: Enum.map(runs, & &1.seed),
         mission_impacts: mission_impacts(graph, runs)
       }}
    end
  end

  defp optimization(%StudyCollectionItem{optimization_run_id: nil} = item),
    do: {:error, item_path(item, "optimization_run_id")}

  defp optimization(%StudyCollectionItem{optimization_run_id: run_id} = item) do
    case cast_id(run_id) do
      {:ok, id} -> stored_optimization(Repo.get(OptimizationRun, id), item)
      :error -> {:error, item_path(item, "optimization_run_id")}
    end
  end

  defp stored_optimization(%OptimizationRun{} = run, _item), do: {:ok, run}

  defp stored_optimization(nil, item),
    do: {:error, item_path(item, "optimization_run_id")}

  defp validate_optimization(%OptimizationRun{} = run, %WorkItem{} = work, item) do
    valid? =
      run.status == "completed" and
        is_binary(run.output_graph_revision_id) and
        run.graph_revision_id == work.graph_revision_id and
        run.strategy == work.strategy.key and
        run.requested_budget == work.budget and
        run.seed == work.selection_seed and
        non_negative_integer?(run.runtime_ms)

    if valid?, do: :ok, else: {:error, item_path(item, "optimization_run_id")}
  end

  defp output_graph(%OptimizationRun{} = run, item) do
    case Graphs.load_revision(run.output_graph_revision_id) do
      %Graph{} = graph -> {:ok, graph}
      _missing -> {:error, item_path(item, "output_graph_revision_id")}
    end
  end

  defp experiment(%StudyCollectionItem{experiment_id: nil} = item),
    do: {:error, item_path(item, "experiment_id")}

  defp experiment(%StudyCollectionItem{experiment_id: experiment_id} = item) do
    case cast_id(experiment_id) do
      {:ok, id} -> stored_experiment(Experiments.load(id), item)
      :error -> {:error, item_path(item, "experiment_id")}
    end
  end

  defp stored_experiment(%Experiment{runs: runs} = experiment, _item) when is_list(runs),
    do: {:ok, experiment, Enum.sort_by(runs, & &1.trial_index)}

  defp stored_experiment(_missing_or_unloaded, item),
    do: {:error, item_path(item, "experiment_id")}

  defp validate_experiment(
         %Experiment{} = experiment,
         %OptimizationRun{} = run,
         %WorkItem{} = work,
         item
       ) do
    valid? =
      experiment.status == :completed and
        experiment.graph_revision_id == run.output_graph_revision_id and
        experiment.master_seed == work.evaluation_root and
        experiment.total_trials == work.attack_count and
        experiment.completed_trials == experiment.total_trials and
        experiment.iteration_count == work.iterations_per_run and
        experiment.max_attempts == work.max_attempts and
        experiment.initial_foothold_node_id == work.initial_foothold_node_id

    if valid?, do: :ok, else: {:error, item_path(item, "experiment_id")}
  end

  defp validate_runs(runs, %Experiment{} = experiment, item) do
    cond do
      length(runs) != experiment.total_trials ->
        {:error, item_path(item, "experiment_id")}

      Enum.map(runs, & &1.trial_index) != Enum.to_list(1..experiment.total_trials) ->
        {:error, item_path(item, "trial_index")}

      not Enum.all?(runs, &RunIdentity.owned_by_experiment?(&1, experiment)) ->
        {:error, item_path(item, "graph_revision_id")}

      not Enum.all?(runs, &non_negative_integer?(&1.runtime_us)) ->
        {:error, item_path(item, "runtime_us")}

      not Enum.all?(runs, &RunIdentity.derived_seed?(&1, experiment)) ->
        {:error, item_path(item, "seed")}

      true ->
        :ok
    end
  end

  defp mission_impacts(%Graph{} = graph, runs) do
    Enum.map(runs, fn run ->
      run
      |> Run.current_attacker_state()
      |> AttackerState.foothold_nodes()
      |> then(&MissionImpact.final(graph, &1))
    end)
  end

  defp comparisons(evidence, %Definition{family: family} = definition) do
    family.comparisons
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {comparison, position}, {:ok, collected} ->
      case comparison_evidence(comparison, position, evidence, definition) do
        {:ok, value} -> {:cont, {:ok, [value | collected]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> reverse()
  end

  defp comparison_evidence(
         %Comparison{} = comparison,
         position,
         evidence,
         %Definition{} = definition
       ) do
    items = Enum.filter(evidence, &(&1.work.comparison_position == position))

    with {:ok, attack_seeds} <- aligned_seeds(items, position),
         {:ok, alternative} <- side(items, :alternative, position),
         {:ok, reference} <- side(items, :reference, position),
         {:ok, identity} <- identity(comparison, position),
         {:ok, provenance} <- provenance(comparison, position, items, definition) do
      {:ok,
       %ComparisonEvidence{
         position: position,
         identity: identity,
         evidence: %Evidence{
           outcome: comparison.outcome,
           attack_seeds: attack_seeds,
           alternative: alternative,
           reference: reference
         },
         provenance: provenance
       }}
    end
  end

  defp aligned_seeds([%{attack_seeds: attack_seeds} | rest], position) do
    if Enum.all?(rest, &(&1.attack_seeds == attack_seeds)),
      do: {:ok, attack_seeds},
      else: {:error, ["comparisons", position, "attack_seeds"]}
  end

  defp aligned_seeds([], position), do: {:error, ["comparisons", position, "attack_seeds"]}

  defp side(items, side, position) do
    matching =
      items
      |> Enum.filter(&(&1.work.side == side))
      |> Enum.sort_by(& &1.work.plan_position)

    case matching do
      [] ->
        {:error, ["comparisons", position, Atom.to_string(side)]}

      [%{work: work} | _rest] ->
        {:ok,
         %ComparisonSide{
           strategy: Atom.to_string(work.strategy.key),
           plans: Enum.map(matching, &plan/1)
         }}
    end
  end

  defp plan(%{optimization: optimization, mission_impacts: mission_impacts}) do
    %PlanEvidence{id: optimization.id, mission_impacts: mission_impacts}
  end

  defp identity(%Comparison{} = comparison, position) do
    attrs = %{
      "tier" => comparison.tier,
      "budget" => comparison.budget,
      "alternative" => Atom.to_string(comparison.alternative),
      "reference" => Atom.to_string(comparison.reference),
      "outcome" => comparison.outcome
    }

    case Identity.new(attrs) do
      {:ok, identity} -> {:ok, identity}
      :error -> {:error, ["comparisons", position, "identity"]}
    end
  end

  defp provenance(%Comparison{} = comparison, position, items, %Definition{} = definition) do
    with {:ok, input_revision} <- declared_revision(comparison, position, definition),
         {:ok, collection_seed} <- evaluation_root(items, position) do
      {:ok,
       %Provenance{
         graph_revision_ids: graph_revision_ids(input_revision, items),
         model_revision: definition.study.revisions.model,
         collection_seed: collection_seed,
         source_run_ids: Enum.flat_map(items, &[&1.optimization.id, &1.experiment.id]),
         environment: definition.study.revisions.environment
       }}
    end
  end

  defp declared_revision(%Comparison{} = comparison, position, %Definition{} = definition) do
    case Enum.find(definition.graphs, &(&1.tier == comparison.tier)) do
      %{graph_revision_id: revision_id} -> {:ok, revision_id}
      nil -> {:error, ["comparisons", position, "provenance"]}
    end
  end

  defp evaluation_root([%{work: work} | _rest], _position), do: {:ok, work.evaluation_root}
  defp evaluation_root([], position), do: {:error, ["comparisons", position, "provenance"]}

  defp graph_revision_ids(input_revision, items) do
    Enum.uniq([input_revision | Enum.map(items, & &1.optimization.output_graph_revision_id)])
  end

  defp item_path(%StudyCollectionItem{item_position: position}, field),
    do: ["collection_items", position, field]

  defp cast_id(value), do: Ecto.UUID.cast(value)

  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp reverse({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse({:error, error}), do: {:error, error}
end
