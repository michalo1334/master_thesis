defmodule NetworkDefense.Evaluation.Study.StudyCollectionActionTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.{Collection, CollectionItems, CollectionLimits}
  alias NetworkDefense.Evaluation.Study.Contracts.{CollectionResult, StudyError}
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyFixtures}
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Simulation.{Experiment, Experiments}

  setup do
    study = StudyFixtures.study_with_two_phases()
    collection = StudyFixtures.insert_collection_graph("study-collection-action")
    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)

    %{
      revision: study.revision,
      execution: study.execution,
      pilot_phase: study.pilot_phase,
      graph: collection.graph,
      foothold: collection.foothold,
      definition: definition
    }
  end

  test "COLLECTION-ACTION-01: one item returns compact linked IDs and completion counts", %{
    execution: execution,
    pilot_phase: phase,
    definition: definition
  } do
    work = work!(execution, phase, definition, 0)
    item = collection_item(phase, work)

    assert {:ok, %CollectionResult{} = result} = Collection.run_collection_item(item, work)

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
             strategy: "null",
             seed: 610_001,
             requested_budget: 1
           } =
             Repo.get(OptimizationRun, optimization_run_id)

    assert %Experiment{status: :completed, completed_trials: 10, total_trials: 10} =
             Experiments.get(experiment_id)
  end

  test "COLLECTION-ACTION-02: a work item that disagrees with the item does no runtime work", %{
    execution: execution,
    pilot_phase: phase,
    definition: definition,
    graph: graph
  } do
    work = work!(execution, phase, definition, 0)
    item = collection_item(phase, work)
    other = work!(execution, phase, definition, 1)

    for mismatched <- [other, %{work | replica_position: 3}] do
      assert {:error, %StudyError{code: "conflict", issues: [issue]}} =
               Collection.run_collection_item(item, mismatched)

      assert issue["code"] == "collection_work_mismatch"
    end

    assert %StudyCollectionItem{optimization_run_id: nil, experiment_id: nil} =
             Repo.get(StudyCollectionItem, item.id)

    assert runtime_record_count(OptimizationRun, graph) == 0
    assert runtime_record_count(Experiment, graph) == 0
  end

  test "COLLECTION-ACTION-03: the item cap is checked before persistence", %{
    execution: execution,
    pilot_phase: phase,
    definition: definition,
    graph: graph
  } do
    work = work!(execution, phase, definition, 1)
    item = collection_item(phase, work)

    original = Application.get_env(:network_defense, CollectionLimits)

    Application.put_env(:network_defense, CollectionLimits,
      max_phase_items: 1,
      max_gust_concurrency: 2
    )

    on_exit(fn ->
      Application.put_env(:network_defense, CollectionLimits, original)
    end)

    assert {:error, %StudyError{issues: [issue]}} = Collection.run_collection_item(item, work)
    assert issue["code"] == "collection_work_limit_exceeded"
    assert Repo.aggregate(from(item in StudyCollectionItem), :count) == 1

    assert %StudyCollectionItem{optimization_run_id: nil, experiment_id: nil} =
             Repo.get(StudyCollectionItem, item.id)

    assert runtime_record_count(OptimizationRun, graph) == 0
    assert runtime_record_count(Experiment, graph) == 0
  end

  defp work!(execution, phase, definition, position) do
    assert {:ok, items} = Collection.build_collection_work(execution, phase, definition, 0)
    Enum.at(items, position)
  end

  defp collection_item(phase, work) do
    assert {:ok, %StudyCollectionItem{} = item} =
             CollectionItems.get_or_create(phase.id, work.replica_position, work.item_position)

    item
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
