defmodule NetworkDefense.Evaluation.Study.FinalCollectionWorkflowTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DagLoader
  alias NetworkDefense.Evaluation.{EvidenceSnapshot, StudyExecution, StudyFixtures, StudyPhase}
  alias NetworkDefense.Evaluation.Study.Actions.AssembleFinalSnapshot
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.FinalCollectionWorkflow

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)

    start_supervised!({DagLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})
    _definitions = DagLoader.get_definitions()
    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    collection =
      StudyFixtures.insert_collection_graph("study-final-collection-dag", mission: true)

    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)
    study = StudyFixtures.study_with_two_phases(definition)
    candidate = hd(definition.pilot.candidates)

    execution =
      study.execution
      |> StudyExecution.changeset(%{
        state: :collecting_final,
        selected_candidate_id: candidate.id,
        selected_plan_count_per_side: candidate.plan_count_per_side,
        selected_attacks_per_plan: candidate.attacks_per_plan,
        pilot_override: false
      })
      |> Repo.update!()

    Map.merge(study, %{definition: definition, execution: execution})
  end

  test "F19-RESCUE-01: WHEN the execution or result is absent, Final collection SHALL keep its bounded errors" do
    phase = %StudyPhase{execution_id: Ecto.UUID.generate()}

    assert FinalCollectionWorkflow.create(phase) ==
             {:error, StudyError.study_execution_not_found()}

    assert FinalCollectionWorkflow.result(9_000_000) ==
             {:error, StudyError.final_collection_workflow_failed()}
  end

  test "F19-02: WHEN the fixed Final collection DAG runs, THE application SHALL persist and return one Final snapshot",
       context do
    assert {:ok, run_id} = FinalCollectionWorkflow.create(context.final_phase)
    assert :ok = FinalCollectionWorkflow.dispatch(run_id)
    assert {:ok, snapshot_id} = FinalCollectionWorkflow.await(run_id, 10_000)
    assert {:ok, ^snapshot_id} = FinalCollectionWorkflow.result(run_id)

    assert %{status: :succeeded} = Gust.Flows.get_run!(run_id)
    assert Repo.get!(StudyPhase, context.final_phase.id).snapshot_id == snapshot_id
    assert Repo.get!(EvidenceSnapshot, snapshot_id).phase == :final

    mapped = Gust.Flows.get_tasks_by_name("collect_final_item", run_id)
    assert mapped != []
    assert Enum.all?(mapped, fn task -> Map.keys(task.params) == ["collection_item_id"] end)

    [first | _rest] = mapped
    first |> Gust.Flows.Task.changeset(%{result: %{}}) |> Gust.Repo.update!()

    assert_raise Gust.DAG.NonRecError, ~r/incomplete_final_evidence/, fn ->
      AssembleFinalSnapshot.execute([], %{run_id: run_id})
    end

    assert Repo.get!(StudyPhase, context.final_phase.id).snapshot_id == snapshot_id
  end
end
