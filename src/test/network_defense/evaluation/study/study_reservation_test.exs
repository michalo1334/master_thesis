defmodule NetworkDefense.Evaluation.Study.StudyReservationTest do
  use NetworkDefense.DataCase, async: false
  use Oban.Testing, repo: NetworkDefense.Repo

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.CollectionItems
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Reservations
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyFixtures}
  alias NetworkDefense.Optimization.{OptimizationRun, OptimizationRuns}
  alias NetworkDefense.Simulation.{Experiment, Experiments, Run}
  alias NetworkDefense.Simulations
  alias NetworkDefense.Simulations.CoordinatorRegistry

  # Three behaviors of the reservation boundary of one collection item:
  #
  # 1. a repeated matching reservation returns the same runtime record;
  # 2. a changed request fails and keeps the original link and record;
  # 3. the reservation stores the record and starts no runtime work.
  #
  # Both runtime sides are covered. The short row lock is the concurrency guard,
  # so no concurrency test repeats it.

  setup do
    study = StudyFixtures.study_with_two_phases()
    Map.merge(study, StudyFixtures.insert_collection_graph("study-reservation"))
  end

  test "RESERVE-01: a repeated optimization reservation returns the stored run", %{
    pilot_phase: phase,
    graph: graph
  } do
    item = collection_item(phase)
    request = StudyFixtures.optimization_request(graph, seed: 7, budget: 1)
    running_tasks = task_supervisor_children()

    assert {:ok, %OptimizationRun{} = run} = Reservations.reserve_optimization(item.id, request)

    assert run.status == "running"
    assert run.graph_revision_id == graph.revision_id
    assert run.strategy == "cvss"
    assert run.requested_budget == 1
    assert run.seed == 7

    assert %{optimization_run_id: run_id} = Repo.get(StudyCollectionItem, item.id)
    assert run_id == run.id

    repeated =
      StudyFixtures.optimization_request(graph,
        seed: 7,
        budget: 1,
        correlation_id: "another-correlation"
      )

    assert {:ok, %OptimizationRun{id: repeated_id}} =
             Reservations.reserve_optimization(item.id, repeated)

    assert repeated_id == run.id
    assert optimization_run_count(graph.revision_id) == 1
    assert [] == all_enqueued()
    assert MapSet.subset?(task_supervisor_children(), running_tasks)
  end

  test "RESERVE-02: a changed optimization request fails and keeps the link", %{
    pilot_phase: phase,
    graph: graph
  } do
    item = collection_item(phase)
    request = StudyFixtures.optimization_request(graph, seed: 7, budget: 1)

    assert {:ok, %OptimizationRun{} = run} = Reservations.reserve_optimization(item.id, request)

    changed_requests = [
      StudyFixtures.optimization_request(graph, budget: 2),
      StudyFixtures.optimization_request(graph, seed: 8),
      StudyFixtures.optimization_request(graph, strategy: "null")
    ]

    for changed <- changed_requests do
      assert {:error, %StudyError{code: "conflict", issues: [issue]}} =
               Reservations.reserve_optimization(item.id, changed)

      assert issue["code"] == "runtime_record_mismatch"
      assert issue["path"] == ["optimization_run_id"]
    end

    assert %{optimization_run_id: linked_id} = Repo.get(StudyCollectionItem, item.id)
    assert linked_id == run.id
    assert optimization_run_count(graph.revision_id) == 1

    assert %OptimizationRun{status: "running", requested_budget: 1, seed: 7} =
             OptimizationRuns.load(run.id)
  end

  test "RESERVE-03: a repeated experiment reservation returns the stored experiment", %{
    pilot_phase: phase,
    graph: graph,
    foothold: foothold
  } do
    item = collection_item(phase)

    assert {:ok, %OptimizationRun{} = run} =
             Reservations.reserve_optimization(item.id, StudyFixtures.optimization_request(graph))

    request = StudyFixtures.simulation_request(graph, foothold, seed: 11, trials: 2)
    running_tasks = task_supervisor_children()
    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

    assert {:ok, %Experiment{} = experiment} = Reservations.reserve_experiment(item.id, request)

    assert experiment.status == :running
    assert experiment.completed_trials == 0
    assert experiment.total_trials == 2
    assert experiment.master_seed == 11
    assert experiment.graph_revision_id == graph.revision_id
    assert experiment.initial_foothold_node_id == foothold.id

    assert %{experiment_id: experiment_id, optimization_run_id: optimization_run_id} =
             Repo.get(StudyCollectionItem, item.id)

    assert experiment_id == experiment.id
    assert optimization_run_id == run.id

    repeated =
      StudyFixtures.simulation_request(graph, foothold,
        seed: 11,
        trials: 2,
        correlation_id: "another-correlation"
      )

    assert {:ok, %Experiment{id: repeated_id}} =
             Reservations.reserve_experiment(item.id, repeated)

    assert repeated_id == experiment.id

    assert experiment_count(graph.revision_id) == 1

    assert [] ==
             Repo.all(from stored_run in Run, where: stored_run.experiment_id == ^experiment.id)

    assert [] == Registry.lookup(CoordinatorRegistry, experiment.id)
    assert [] == all_enqueued()
    assert MapSet.subset?(task_supervisor_children(), running_tasks)
    refute_receive {:simulation_progress, _progress}, 50
  end

  test "RESERVE-04: a generated seed stays outside the experiment identity", %{
    pilot_phase: phase,
    graph: graph,
    foothold: foothold
  } do
    item = collection_item(phase)
    request = StudyFixtures.simulation_request(graph, foothold, generate_seed: true, seed: nil)

    assert {:ok, %Experiment{} = experiment} = Reservations.reserve_experiment(item.id, request)
    assert is_integer(experiment.master_seed)

    assert {:ok, %Experiment{id: repeated_id}} = Reservations.reserve_experiment(item.id, request)
    assert repeated_id == experiment.id
    assert experiment_count(graph.revision_id) == 1
  end

  test "RESERVE-05: a changed experiment request fails and keeps the link", %{
    pilot_phase: phase,
    graph: graph,
    foothold: foothold,
    alternate_foothold: alternate_foothold
  } do
    item = collection_item(phase)
    request = StudyFixtures.simulation_request(graph, foothold, seed: 11, trials: 2)

    assert {:ok, %Experiment{} = experiment} = Reservations.reserve_experiment(item.id, request)

    changed_requests = [
      StudyFixtures.simulation_request(graph, foothold, seed: 11, trials: 3),
      StudyFixtures.simulation_request(graph, foothold, seed: 12),
      StudyFixtures.simulation_request(graph, foothold, seed: 11, iterations: 2),
      StudyFixtures.simulation_request(graph, foothold, seed: 11, max_attempts: 2),
      StudyFixtures.simulation_request(graph, alternate_foothold, seed: 11)
    ]

    for changed <- changed_requests do
      assert {:error, %StudyError{code: "conflict", issues: [issue]}} =
               Reservations.reserve_experiment(item.id, changed)

      assert issue["code"] == "runtime_record_mismatch"
      assert issue["path"] == ["experiment_id"]
    end

    assert %{experiment_id: linked_id} = Repo.get(StudyCollectionItem, item.id)
    assert linked_id == experiment.id
    assert experiment_count(graph.revision_id) == 1

    assert %Experiment{status: :running, total_trials: 2, master_seed: 11} =
             Experiments.get(experiment.id)
  end

  test "RESERVE-06: invalid simulation preparation fails without an experiment", %{
    pilot_phase: phase,
    graph: graph
  } do
    item = collection_item(phase)
    invalid_foothold = %{id: Ecto.UUID.generate()}
    request = StudyFixtures.simulation_request(graph, invalid_foothold)

    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Reservations.reserve_experiment(item.id, request)

    assert issue["code"] == "runtime_request_invalid"
    assert issue["path"] == ["experiment_id"]
    assert %{experiment_id: nil} = Repo.get(StudyCollectionItem, item.id)
    assert experiment_count(graph.revision_id) == 0
  end

  test "RESERVE-07: invalid optimization preparation fails without a run", %{
    pilot_phase: phase,
    graph: graph
  } do
    item = collection_item(phase)

    request =
      StudyFixtures.simulation_backed_optimization_request(graph, Ecto.UUID.generate())

    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Reservations.reserve_optimization(item.id, request)

    assert issue["code"] == "runtime_request_invalid"
    assert issue["path"] == ["optimization_run_id"]
    assert %{optimization_run_id: nil} = Repo.get(StudyCollectionItem, item.id)
    assert optimization_run_count(graph.revision_id) == 0
  end

  test "RESERVE-08: an unknown collection item fails without a runtime record", %{
    graph: graph,
    foothold: foothold
  } do
    item_id = Ecto.UUID.generate()

    assert {:error, %StudyError{issues: [optimization_issue]}} =
             Reservations.reserve_optimization(item_id, StudyFixtures.optimization_request(graph))

    assert optimization_issue["code"] == "collection_item_not_found"

    assert {:error, %StudyError{issues: [experiment_issue]}} =
             Reservations.reserve_experiment(
               item_id,
               StudyFixtures.simulation_request(graph, foothold)
             )

    assert experiment_issue["code"] == "collection_item_not_found"

    assert optimization_run_count(graph.revision_id) == 0
    assert experiment_count(graph.revision_id) == 0
  end

  defp collection_item(phase) do
    assert {:ok, %StudyCollectionItem{} = item} = CollectionItems.get_or_create(phase.id, 0, 0)
    item
  end

  defp optimization_run_count(graph_revision_id) do
    Repo.aggregate(
      from(run in OptimizationRun, where: run.graph_revision_id == ^graph_revision_id),
      :count
    )
  end

  defp experiment_count(graph_revision_id) do
    Repo.aggregate(
      from(experiment in Experiment, where: experiment.graph_revision_id == ^graph_revision_id),
      :count
    )
  end

  defp task_supervisor_children do
    NetworkDefense.TaskSupervisor
    |> Task.Supervisor.children()
    |> MapSet.new()
  end
end
