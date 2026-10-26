defmodule NetworkDefense.Evaluation.Study.StudyCollectionActionTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Actions.CollectItem
  alias NetworkDefense.Evaluation.Study.{Collection, CollectionItems, CollectionLimits}
  alias NetworkDefense.Evaluation.Study.Contracts.{CollectionResult, StudyError}
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyFixtures}
  alias NetworkDefense.Optimization.{ExecutionConfig, OptimizationRun}
  alias NetworkDefense.Simulation.{Experiment, Experiments}

  setup do
    collection = StudyFixtures.insert_collection_graph("study-collection-action")
    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)
    study = StudyFixtures.study_with_two_phases(definition)
    Map.merge(study, collection) |> Map.put(:definition, definition)
  end

  test "COLLECTION-ACTION-01: one item returns compact linked IDs and completion counts", %{
    pilot_phase: phase,
    definition: definition
  } do
    item = collection_item(phase, 0)

    assert {:ok, %CollectionResult{} = result} = Collection.run_collection_item(item.id)

    assert result.collection_item_id == item.id
    assert result.replica_position == 0
    assert result.item_position == 0
    assert result.completed_trials == 10
    assert result.total_trials == 10

    assert compact_fields() == result |> Map.from_struct() |> Map.keys() |> Enum.sort()

    assert %StudyCollectionItem{
             optimization_run_id: optimization_run_id,
             experiment_id: experiment_id
           } = Repo.get(StudyCollectionItem, item.id)

    assert result.optimization_run_id == optimization_run_id
    assert result.experiment_id == experiment_id

    assert %OptimizationRun{
             status: "completed",
             strategy: :null,
             seed: 610_001,
             requested_budget: 1
           } =
             Repo.get(OptimizationRun, optimization_run_id)

    assert %Experiment{status: :completed, completed_trials: 10, total_trials: 10} =
             Experiments.get(experiment_id)

    assert %Experiment{
             rules: rules,
             require_pre_attack_feasibility: true
           } = Experiments.get(experiment_id)

    assert rules == definition.simulation.rules
  end

  test "RCOLL-01: a malformed external item identifier returns the bounded not-found error" do
    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Collection.run_collection_item("not-a-uuid")

    assert issue["code"] == "collection_item_not_found"
    assert issue["path"] == ["id"]
  end

  test "COLLECTION-ACTION-02: an item position outside the canonical work creates no runtime record",
       %{pilot_phase: phase, graph: graph} do
    item = collection_item(phase, 10_000)

    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Collection.run_collection_item(item.id)

    assert issue["code"] == "invalid_collection_position"

    assert %StudyCollectionItem{optimization_run_id: nil, experiment_id: nil} =
             Repo.get(StudyCollectionItem, item.id)

    assert runtime_record_count(OptimizationRun, graph) == 0
    assert runtime_record_count(Experiment, graph) == 0
  end

  test "COLLECTION-ACTION-03: the item cap is checked before persistence", %{
    pilot_phase: phase,
    graph: graph
  } do
    item = collection_item(phase, 1)

    original = Application.get_env(:network_defense, CollectionLimits)

    Application.put_env(:network_defense, CollectionLimits,
      max_phase_items: 1,
      max_gust_concurrency: 2
    )

    on_exit(fn ->
      Application.put_env(:network_defense, CollectionLimits, original)
    end)

    assert {:error, %StudyError{issues: [issue]}} = Collection.run_collection_item(item.id)
    assert issue["code"] == "collection_work_limit_exceeded"
    assert Repo.aggregate(from(item in StudyCollectionItem), :count) == 1

    assert %StudyCollectionItem{optimization_run_id: nil, experiment_id: nil} =
             Repo.get(StudyCollectionItem, item.id)

    assert runtime_record_count(OptimizationRun, graph) == 0
    assert runtime_record_count(Experiment, graph) == 0
  end

  test "COLLECTION-ACTION-04: a mapped task rebuilds its work from the stored revision", %{
    pilot_phase: phase,
    definition: definition,
    graph: graph
  } do
    item = collection_item(phase, 0)

    assert %{"optimization_run_id" => run_id} =
             CollectItem.execute([collection_item_id: item.id], %{run_id: 1})

    assert %OptimizationRun{execution_config: execution_config} =
             Repo.get(OptimizationRun, run_id)

    assert %ExecutionConfig{
             candidate_action_types: candidate_action_types,
             require_pre_attack_feasibility: require_pre_attack_feasibility,
             initial_foothold_node_id: nil,
             scoring: nil
           } = execution_config

    assert Enum.map(candidate_action_types, &Atom.to_string/1) ==
             declared_actions(definition, "null")

    assert require_pre_attack_feasibility == declared_feasibility(definition, "null")

    assert_raise Gust.DAG.NonRecError, fn ->
      CollectItem.execute([collection_item_id: Ecto.UUID.generate()], %{run_id: 1})
    end

    assert runtime_record_count(OptimizationRun, graph) == 1
  end

  test "COLLECTION-ACTION-05: an unsupported phase creates no runtime record", %{
    execution: execution,
    graph: graph
  } do
    phase = StudyFixtures.insert_phase(execution, :final_analysis)
    item = collection_item(phase, 0)

    assert {:error, %StudyError{issues: [issue]}} = Collection.run_collection_item(item.id)
    assert issue["code"] == "unsupported_collection_phase"

    assert %StudyCollectionItem{optimization_run_id: nil, experiment_id: nil} =
             Repo.get(StudyCollectionItem, item.id)

    assert runtime_record_count(OptimizationRun, graph) == 0
    assert runtime_record_count(Experiment, graph) == 0
  end

  test "COLLECTION-ACTION-06: a retry reuses the linked records without a scientific request", %{
    pilot_phase: phase
  } do
    item = collection_item(phase, 0)

    assert {:ok, %CollectionResult{} = first} = Collection.run_collection_item(item.id)
    assert {:ok, %CollectionResult{} = repeated} = Collection.run_collection_item(item.id)

    assert repeated.optimization_run_id == first.optimization_run_id
    assert repeated.experiment_id == first.experiment_id

    assert Repo.aggregate(from(item in StudyCollectionItem), :count) == 1
  end

  defp collection_item(phase, position) do
    assert {:ok, %StudyCollectionItem{} = item} =
             CollectionItems.get_or_create(phase.id, 0, position)

    item
  end

  defp declared_actions(definition, key) do
    definition.graphs
    |> Enum.flat_map(& &1.strategies)
    |> Enum.find(&(&1.key == String.to_existing_atom(key)))
    |> Map.fetch!(:candidate_action_types)
    |> Enum.map(&Atom.to_string/1)
  end

  defp declared_feasibility(definition, key) do
    definition.graphs
    |> Enum.flat_map(& &1.strategies)
    |> Enum.find(&(&1.key == String.to_existing_atom(key)))
    |> Map.fetch!(:require_pre_attack_feasibility)
  end

  defp compact_fields do
    [
      :collection_item_id,
      :completed_trials,
      :experiment_id,
      :item_position,
      :optimization_run_id,
      :replica_position,
      :total_trials
    ]
  end

  defp runtime_record_count(schema, graph) do
    Repo.aggregate(
      from(record in schema, where: record.graph_revision_id == ^graph.revision_id),
      :count
    )
  end
end
