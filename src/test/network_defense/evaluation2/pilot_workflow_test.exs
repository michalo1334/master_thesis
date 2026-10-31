defmodule NetworkDefense.Evaluation2.PilotWorkflowTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DAGLoader
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Persistence, Workflow}
  alias NetworkDefense.Evaluation2Test.{FoundationFixtures, GraphFixtures}

  @moduletag :integration
  @moduletag case_id:
               "BIND-01/BIND-02/FLOW-01/FLOW-02/FLOW-03/FLOW-04/PILOT-01/PILOT-02/RESULT-01"
  @moduletag timeout: 30_000

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    start_supervised!({DAGLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})
    DAGLoader.get_definitions()
    opts = GraphFixtures.insert_tiers() |> GraphFixtures.document_opts()

    attrs =
      FoundationFixtures.valid_attrs(opts)
      |> put_in(["pilot", "candidates"], [%{"id" => "one", "plans" => 1, "attacks" => 2}])
      |> put_in(["pilot", "extra_pool"], %{"plans" => 0, "attacks" => 0})
      |> put_in(["pilot", "precision", "outer_subsamples"], 2)
      |> put_in(["simulation", "iterations_per_run"], 2)
      |> update_in(["tiers"], fn tiers ->
        Map.new(tiers, fn {tier, input} ->
          {tier,
           %{
             input
             | "budgets" => [1],
               "alternatives" => [
                 %{"strategy" => "random"},
                 %{
                   "strategy" => "simulation_informed",
                   "scoring" => %{"objective" => "mission_impact_only", "monte_carlo_trials" => 1}
                 }
               ]
           }}
        end)
      end)

    {:ok, revision} = Study.create_revision(Jason.encode!(attrs))
    %{revision: revision}
  end

  test "FLOW-01/PILOT-01/RESULT-01 WHEN the real Pilot completes THEN continue SHALL return an accepted complete report",
       c do
    assert {:ok, started} = Study.start(c.revision)
    assert {:error, _} = Study.pilot_result(started.execution_id)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    assert {:ok, finished} = Study.continue(started.execution_id)
    assert finished.state == :awaiting_final
    assert finished.pilot_outcome.outcome == :insufficient
    assert {:ok, report} = Study.pilot_result(finished.execution_id)
    assert report.outcome == finished.pilot_outcome
    assert [candidate] = report.candidates
    assert candidate.id == "one"
    assert Enum.count(candidate.comparisons) == 6
    assert Enum.uniq(Enum.map(candidate.comparisons, & &1.identity)) |> Enum.count() == 6
    assert Enum.all?(candidate.comparisons, &(&1.guarded_half_width > 0.0))
    assert Enum.all?(candidate.comparisons, &(not &1.passes))
    assert candidate.predicted_runtime_ms >= 0

    assert {:ok, collection} =
             Persistence.fetch_execution_phase(finished.execution_id, :pilot_collection)

    assert {:ok, snapshot} = Persistence.fetch_phase_evidence_snapshot(collection.id)
    assert snapshot.evidence.comparisons != []

    assert {:ok, analysis} =
             Persistence.fetch_execution_phase(finished.execution_id, :pilot_analysis)

    assert {:ok, [canonical]} = Persistence.list_phase_runs(analysis.id)
    assert {:ok, _output} = Workflow.pilot_analysis_result(canonical.id)
    assert {:ok, retried} = Study.continue(finished.execution_id, timeout: 0)
    assert retried == finished
    assert {:ok, [same]} = Persistence.list_phase_runs(analysis.id)
    assert same.id == canonical.id
    assert {:ok, again} = Study.pilot_result(finished.execution_id)
    assert again == report
    assert {:error, _} = Study.resume(finished.execution_id, :recommended)
    assert {:ok, %{state: :awaiting_final}} = Study.status(finished.execution_id)
    assert {:ok, approved} = Study.resume(finished.execution_id, {:override_insufficient, "one"})
    assert approved.state == :collecting_final
    assert approved.selection.plan_count_per_side == 1
    assert approved.selection.attacks_per_plan == 2

    assert {:ok, final_phase} =
             Persistence.fetch_execution_phase(finished.execution_id, :final_collection)

    assert {:ok, %{run_key: :small}} = Persistence.fetch_phase_run(final_phase.id, :small)
  end

  test "FLOW-03 WHEN continue times out THEN the execution and canonical run SHALL remain active",
       c do
    assert {:ok, started} = Study.start(c.revision)
    assert {:ok, returned} = Study.continue(started.execution_id, timeout: 1)
    assert returned.state == :collecting_pilot
    assert returned.error == nil

    assert {:ok, phase} =
             Persistence.fetch_execution_phase(started.execution_id, :pilot_collection)

    assert {:ok, before} = Persistence.fetch_phase_run(phase.id, :single)
    assert {:ok, same} = Workflow.ensure_next_run(started.execution_id)
    assert same.id == before.id
    assert {:ok, cancelled} = Study.cancel(started.execution_id)
    assert cancelled.state == :cancelled
    assert Gust.Repo.get!(Gust.Flows.Run, before.gust_run_id).status == :failed
    assert {:ok, terminal} = Study.continue(started.execution_id)
    assert terminal.state == :cancelled
  end

  test "BIND-01 WHEN callers continue concurrently THEN both SHALL converge on the canonical runs",
       c do
    assert {:ok, started} = Study.start(c.revision)
    parent = self()

    callers =
      for _index <- 1..2 do
        Task.async(fn ->
          send(parent, :caller_started)
          Study.continue(started.execution_id, timeout: 15_000)
        end)
      end

    assert_receive :caller_started
    assert_receive :caller_started
    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    for caller <- callers do
      assert {:ok, %{state: :awaiting_final}} = Task.await(caller, 17_000)
    end

    for kind <- [:pilot_collection, :pilot_analysis] do
      assert {:ok, phase} = Persistence.fetch_execution_phase(started.execution_id, kind)
      assert {:ok, [_canonical]} = Persistence.list_phase_runs(phase.id)
    end
  end

  test "FLOW-04 WHEN another caller cancels durable state THEN blocked continuation SHALL observe it",
       c do
    assert {:ok, started} = Study.start(c.revision)
    parent = self()

    continuing =
      Task.async(fn ->
        send(parent, :continuation_started)
        Study.continue(started.execution_id)
      end)

    assert_receive :continuation_started
    assert {:ok, _context} = Persistence.Executions.cancel_execution(started.execution_id)
    assert {:ok, %{state: :cancelled}} = Task.await(continuing, 2_000)
    assert {:error, _} = Persistence.fetch_execution_phase(started.execution_id, :pilot_analysis)
  end

  test "BIND-02/PILOT-01 WHEN a successful terminal omits a comparison THEN acceptance SHALL stay pending",
       c do
    assert {:ok, started} = Study.start(c.revision)

    assert {:ok, collection} =
             Persistence.fetch_execution_phase(started.execution_id, :pilot_collection)

    assert {:ok, collection_run} = Persistence.fetch_phase_run(collection.id, :single)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    assert {:ok, :terminal} =
             Workflow.RunMonitor.await(collection_run.gust_run_id, started.execution_id, 15_000)

    assert {:ok, _receipt} = Workflow.pilot_collection_result(collection_run.id)
    assert {:ok, context} = Persistence.Executions.accept_pilot_collection(collection.id)
    assert {:ok, analysis_run} = Workflow.ensure_pilot_analysis_run(context.active_phase.id)

    assert {:ok, :terminal} =
             Workflow.RunMonitor.await(analysis_run.gust_run_id, started.execution_id, 15_000)

    [terminal] = Gust.Flows.get_tasks_by_name("select_pilot_outcome", analysis_run.gust_run_id)
    [candidate] = terminal.result["candidates"]

    incomplete =
      put_in(terminal.result, ["candidates"], [
        %{candidate | "comparisons" => tl(candidate["comparisons"])}
      ])

    Gust.Repo.update!(Ecto.Changeset.change(terminal, result: incomplete))
    assert {:error, _} = Study.continue(started.execution_id, timeout: 1_000)
    assert {:ok, %{state: :analyzing_pilot}} = Study.status(started.execution_id)
    stored_terminal = Gust.Repo.get!(Gust.Flows.Task, terminal.id)
    Gust.Repo.update!(Ecto.Changeset.change(stored_terminal, result: terminal.result))
    assert {:ok, %{state: :awaiting_final}} = Study.continue(started.execution_id, timeout: 1_000)
  end

  test "BIND-01/FLOW-04 WHEN cancellation wins before a new canonical link THEN provisioning SHALL stay inert",
       c do
    collected = completed_collection(c.revision)
    {:ok, context} = Persistence.Executions.accept_pilot_collection(collected.phase.id)
    :meck.new(Persistence, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Persistence) end)
    # Force cancellation after Workflow's active-state read, before link commit.
    :meck.expect(Persistence, :link_phase_run, fn phase_id, key, proposed_id, run_id ->
      send(self(), {:rejected_created_run, run_id})
      {:ok, _cancelled} = Persistence.Executions.cancel_execution(collected.execution_id)
      :meck.passthrough([phase_id, key, proposed_id, run_id])
    end)

    assert {:error, _} = Workflow.ensure_pilot_analysis_run(context.active_phase.id)
    assert {:error, _} = Persistence.fetch_phase_run(context.active_phase.id, :single)
    assert_receive {:rejected_created_run, rejected_id}
    assert Gust.Repo.get(Gust.Flows.Run, rejected_id) == nil
    assert {:ok, %{state: :cancelled}} = Study.status(collected.execution_id)
  end

  test "FLOW-04 WHEN valid collection proof arrives after cancellation THEN acceptance SHALL create no successor",
       c do
    collected = completed_collection(c.revision)
    assert {:ok, %{state: :cancelled}} = Study.cancel(collected.execution_id)
    assert {:ok, _valid_late_receipt} = Workflow.pilot_collection_result(collected.run.id)
    assert {:error, _} = Persistence.Executions.accept_pilot_collection(collected.phase.id)

    assert {:error, _} =
             Persistence.fetch_execution_phase(collected.execution_id, :pilot_analysis)

    assert {:ok, %{state: :cancelled}} = Study.continue(collected.execution_id)
  end

  test "FLOW-01 WHEN the canonical Gust run fails THEN continuation SHALL return a durable failed status",
       c do
    assert {:ok, started} = Study.start(c.revision)

    assert {:ok, phase} =
             Persistence.fetch_execution_phase(started.execution_id, :pilot_collection)

    assert {:ok, phase_run} = Persistence.fetch_phase_run(phase.id, :single)
    run = Gust.Repo.get!(Gust.Flows.Run, phase_run.gust_run_id)
    assert {:ok, _failed} = Gust.Flows.update_run_status(run, :failed)
    assert {:ok, failed} = Study.continue(started.execution_id)
    assert failed.state == :failed
    assert [%{code: "pilot_run_failed"}] = failed.error.issues
    assert {:ok, same} = Study.continue(started.execution_id)
    assert same == failed
    assert {:error, _} = Study.pilot_result(started.execution_id)
    assert {:error, _} = Persistence.fetch_execution_phase(started.execution_id, :pilot_analysis)
  end

  test "BIND-01 WHEN another caller advances after the context read THEN continuation SHALL reload the successor",
       c do
    collected = completed_collection(c.revision)
    barrier = :atomics.new(1, [])
    :meck.new(Persistence, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Persistence) end)
    # Control only the storage-read boundary. Proof, acceptance transactions,
    # effects and subsequent reads stay real. This forces the stale-read race.
    :meck.expect(Persistence, :fetch_phase_context, fn phase_id ->
      if phase_id == collected.phase.id and :atomics.add_get(barrier, 1, 1) == 1 do
        {:ok, _successor} = Persistence.Executions.accept_pilot_collection(phase_id)
      end

      :meck.passthrough([phase_id])
    end)

    assert {:ok, %{state: :awaiting_final}} =
             Study.continue(collected.execution_id, timeout: 15_000)

    assert :atomics.get(barrier, 1) == 1
  end

  test "PILOT-02 WHEN runtime effects are incomplete THEN cost sampling SHALL reject them", c do
    collected = completed_collection(c.revision)
    store = Persistence.Collection
    assert {:ok, plan} = store.fetch_collection_plan(collected.run.id)
    assert {:ok, _warmup} = store.prepare_collection_items(plan.id, -1)
    assert {:ok, [item | _]} = store.list_replica_items(collected.run.id, 0)

    optimization =
      Repo.get!(NetworkDefense.Optimization.OptimizationRun, item.optimization_run_id)

    experiment = Repo.get!(NetworkDefense.Simulation.Experiment, item.experiment_id)
    Repo.update!(Ecto.Changeset.change(optimization, runtime_ms: 100))
    Repo.update!(Ecto.Changeset.change(experiment, runtime_ms: 200))
    assert {:ok, samples} = store.runtime_samples(collected.run.id)
    assert Enum.count(samples.plan_ms) == 9
    assert hd(samples.plan_ms) == 100
    assert hd(samples.attack_ms) == 100.0
    change_effect(NetworkDefense.Optimization.OptimizationRun, optimization.id, status: "failed")
    assert {:error, _} = store.runtime_samples(collected.run.id)

    change_effect(NetworkDefense.Optimization.OptimizationRun, optimization.id,
      status: "completed"
    )

    change_effect(NetworkDefense.Simulation.Experiment, experiment.id, status: :failed)
    assert {:error, _} = store.runtime_samples(collected.run.id)

    change_effect(NetworkDefense.Simulation.Experiment, experiment.id, status: :completed)

    invalid_trials =
      Repo.get!(NetworkDefense.Simulation.Experiment, experiment.id)
      |> Ecto.Changeset.change(total_trials: 0, completed_trials: 0)
      |> Ecto.Changeset.check_constraint(:total_trials, name: :experiments_total_trials_positive)

    assert {:error, _changeset} = Repo.update(invalid_trials, mode: :savepoint)
    assert {:ok, _samples} = store.runtime_samples(collected.run.id)
    change_effect(Persistence.CollectionItem, item.id, optimization_run_id: nil)
    assert {:error, _} = store.runtime_samples(collected.run.id)
    assert {:error, _} = store.runtime_samples(Ecto.UUID.generate())
  end

  test "BIND-02 WHEN analysis actions name a foreign owner THEN the boundary SHALL reject them",
       c do
    alias NetworkDefense.Evaluation2.Study.Workflow.PilotAnalysis.Actions.Boundary
    collected = completed_collection(c.revision)

    assert {:ok, %{state: :awaiting_final}} =
             Study.continue(collected.execution_id, timeout: 15_000)

    assert {:ok, analysis} =
             Persistence.fetch_execution_phase(collected.execution_id, :pilot_analysis)

    assert {:ok, analysis_run} = Persistence.fetch_phase_run(analysis.id, :single)
    run = Gust.Repo.get!(Gust.Flows.Run, analysis_run.gust_run_id)

    assert {:error, :foreign_run} =
             Boundary.run_context(run.params, %{run_id: collected.run.gust_run_id})

    collection_params = Map.put(run.params, "study_phase_run_id", collected.run.id)

    assert {:error, :foreign_phase} =
             Boundary.run_context(collection_params, %{run_id: collected.run.gust_run_id})

    assert {:ok, other} = Persistence.Executions.start_execution(c.revision)

    assert {:ok, foreign_snapshot} =
             Persistence.insert_evidence_snapshot(
               other.active_phase.id,
               collected.snapshot.evidence
             )

    foreign_params = Map.put(run.params, "study_evidence_snapshot_id", foreign_snapshot.id)
    assert {:error, :foreign_snapshot} = Boundary.run_context(foreign_params, %{run_id: run.id})
  end

  test "BIND-02 WHEN a successful analysis names another snapshot THEN its report SHALL be rejected",
       c do
    assert {:ok, started} = Study.start(c.revision)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    assert {:ok, %{state: :awaiting_final}} =
             Study.continue(started.execution_id, timeout: 15_000)

    assert {:ok, phase} = Persistence.fetch_execution_phase(started.execution_id, :pilot_analysis)
    assert {:ok, phase_run} = Persistence.fetch_phase_run(phase.id, :single)
    run = Gust.Repo.get!(Gust.Flows.Run, phase_run.gust_run_id)
    params = Map.put(run.params, "study_evidence_snapshot_id", Ecto.UUID.generate())
    Gust.Repo.update!(Ecto.Changeset.change(run, params: params))
    assert {:error, _} = Workflow.pilot_analysis_result(phase_run.id)
    assert {:error, _} = Study.pilot_result(started.execution_id)
    assert {:ok, %{state: :awaiting_final}} = Study.status(started.execution_id)
  end

  defp change_effect(module, id, changes) do
    module |> Repo.get!(id) |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  defp completed_collection(revision) do
    {:ok, started} = Study.start(revision)
    {:ok, phase} = Persistence.fetch_execution_phase(started.execution_id, :pilot_collection)
    {:ok, run} = Persistence.fetch_phase_run(phase.id, :single)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    {:ok, :terminal} = Workflow.RunMonitor.await(run.gust_run_id, started.execution_id, 15_000)
    {:ok, _receipt} = Workflow.pilot_collection_result(run.id)
    {:ok, snapshot} = Persistence.fetch_phase_evidence_snapshot(phase.id)
    %{execution_id: started.execution_id, phase: phase, run: run, snapshot: snapshot}
  end
end
