defmodule NetworkDefense.Evaluation.Study.StudyCollectionWorkflowActionsTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DagLoader
  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Study.Actions.{AssemblePilotSnapshot, PreparePilotCollection}
  alias NetworkDefense.Evaluation.Study.{Collection, CollectionLimits, CollectionWorkflow}
  alias NetworkDefense.Evaluation.Study.Contracts.CollectionResult
  alias NetworkDefense.Evaluation.{StudyFixtures, StudyPhase}

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)

    start_supervised!({DagLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})
    _definitions = DagLoader.get_definitions()
    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    collection = StudyFixtures.insert_collection_graph("study-collection-workflow", mission: true)
    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)
    study = StudyFixtures.study_with_two_phases(definition)

    {:ok, dag} =
      Gust.Flows.create_dag(%{
        name: "study_collection_actions_#{System.unique_integer([:positive])}"
      })

    {:ok, run} =
      Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: %{"study_phase_id" => study.pilot_phase.id}
      })

    Map.merge(study, %{definition: definition, run: run})
  end

  test "STUDY-COLLECTION-02: preparation maps only stable IDs and reuses positional rows",
       context do
    first = PreparePilotCollection.execute([], %{run_id: context.run.id})
    second = PreparePilotCollection.execute([], %{run_id: context.run.id})

    assert first == second
    assert %{"gust_task_items" => payloads} = first
    assert Enum.all?(payloads, fn payload -> Map.keys(payload) == ["collection_item_id"] end)
    assert length(Enum.uniq_by(payloads, & &1["collection_item_id"])) == length(payloads)
  end

  test "STUDY-COLLECTION-03: the phase cap is checked before Gust run creation", context do
    original = Application.fetch_env!(:network_defense, CollectionLimits)

    Application.put_env(:network_defense, CollectionLimits,
      max_phase_items: 9,
      max_gust_concurrency: 2
    )

    on_exit(fn -> Application.put_env(:network_defense, CollectionLimits, original) end)

    before_count = Gust.Repo.aggregate(Gust.Flows.Run, :count)

    assert {:error, %NetworkDefense.Evaluation.Study.Contracts.StudyError{}} =
             CollectionWorkflow.create(context.pilot_phase)

    assert Gust.Repo.aggregate(Gust.Flows.Run, :count) == before_count
  end

  test "STUDY-COLLECTION-04: the fixed Gust DAG completes by callback and direct message with ID-only mapping",
       context do
    assert {:ok, run_id} = CollectionWorkflow.create(context.pilot_phase)
    assert :ok = CollectionWorkflow.dispatch(run_id)
    result = CollectionWorkflow.await(run_id, 10_000)

    snapshot_id =
      case result do
        {:ok, snapshot_id} ->
          snapshot_id

        error ->
          flunk(
            inspect(%{
              error: error,
              run: Gust.Flows.get_run!(run_id).status,
              tasks:
                Gust.Flows.get_run_with_tasks!(run_id).tasks
                |> Enum.map(&{&1.name, &1.map_index, &1.status, &1.error})
            })
          )
      end

    assert %{status: :succeeded} = Gust.Flows.get_run!(run_id)
    assert Repo.get!(StudyPhase, context.pilot_phase.id).snapshot_id == snapshot_id

    mapped = Gust.Flows.get_tasks_by_name("collect_pilot_item", run_id)
    assert mapped != []
    assert Enum.all?(mapped, fn task -> Map.keys(task.params) == ["collection_item_id"] end)

    assert [%{result: %{"snapshot_id" => ^snapshot_id}}] =
             Gust.Flows.get_tasks_by_name("assemble_pilot_snapshot", run_id)
  end

  test "STUDY-COLLECTION-05: fan-in stores only a snapshot ID and rejects changed coverage",
       context do
    %{"gust_task_items" => payloads} =
      preparation = PreparePilotCollection.execute([], %{run_id: context.run.id})

    {:ok, _prepare_task} =
      Gust.Flows.create_task(%{
        name: "prepare_pilot_collection",
        run_id: context.run.id,
        status: :succeeded,
        result: preparation
      })

    tasks =
      payloads
      |> Enum.with_index()
      |> Enum.map(fn {payload, index} ->
        assert {:ok, result} = Collection.run_collection_item(payload["collection_item_id"])

        {:ok, task} =
          Gust.Flows.create_task(%{
            name: "collect_pilot_item",
            run_id: context.run.id,
            map_index: index,
            status: :succeeded,
            params: payload,
            result: CollectionResult.to_params(result)
          })

        task
      end)

    assert %{"snapshot_id" => snapshot_id} =
             AssemblePilotSnapshot.execute([], %{run_id: context.run.id})

    assert {:ok, ^snapshot_id} = Ecto.UUID.cast(snapshot_id)
    assert Repo.get!(StudyPhase, context.pilot_phase.id).snapshot_id == snapshot_id
    assert Repo.aggregate(EvidenceSnapshot, :count) == 1

    [first | _rest] = tasks

    first
    |> Gust.Flows.Task.changeset(%{result: %{}})
    |> Gust.Repo.update!()

    assert_raise Gust.DAG.NonRecError, ~r/incomplete_pilot_evidence/, fn ->
      AssemblePilotSnapshot.execute([], %{run_id: context.run.id})
    end

    assert Repo.aggregate(EvidenceSnapshot, :count) == 1
  end
end
