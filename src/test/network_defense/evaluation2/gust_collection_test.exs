defmodule NetworkDefense.Evaluation2.GustCollectionTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DAGLoader
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Definition, Persistence, Workflow}
  alias NetworkDefense.Evaluation2Test.{FoundationFixtures, GraphFixtures}

  @moduletag :integration
  @moduletag case_id: "COL-01/COL-02/COL-04/SETUP-01"

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    start_supervised!({DAGLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})

    # The synchronous read follows the loader's bootstrap continuation.
    DAGLoader.get_definitions()
    :ok
  end

  test "WHEN Gust executes the grouped Pilot DAG THEN real effects and canonical completion remain readable" do
    opts = GraphFixtures.insert_tiers() |> GraphFixtures.document_opts()
    attrs = FoundationFixtures.valid_attrs(opts)

    attrs =
      put_in(attrs, ["pilot", "candidates"], [%{"id" => "one", "plans" => 1, "attacks" => 2}])

    attrs = put_in(attrs, ["pilot", "extra_pool"], %{"plans" => 0, "attacks" => 0})
    attrs = put_in(attrs, ["simulation", "iterations_per_run"], 2)

    attrs =
      update_in(attrs, ["tiers"], fn tiers ->
        Map.new(tiers, fn {tier, input} ->
          alternatives = [
            %{"strategy" => "random"},
            %{
              "strategy" => "simulation_informed",
              "scoring" => %{"objective" => "mission_impact_only", "monte_carlo_trials" => 1}
            }
          ]

          {tier, %{input | "budgets" => [1], "alternatives" => alternatives}}
        end)
      end)

    assert {:ok, revision} = Study.create_revision(Jason.encode!(attrs))
    assert {:ok, status} = Study.start(revision)
    assert {:ok, {execution, _revision}} = Persistence.fetch_execution(status.execution_id)

    phase =
      Repo.get_by!(Persistence.Phase, study_execution_id: execution.id, phase: :pilot_collection)

    assert {:ok, phase_run} = Persistence.fetch_phase_run(phase.id, :single)
    Gust.PubSub.subscribe_run(phase_run.gust_run_id)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    run_id = phase_run.gust_run_id

    assert_receive {:dag, :run_status, %{run_id: ^run_id, status: :succeeded, task_id: nil}},
                   15_000

    assert {:ok, _output} = Workflow.pilot_collection_result(phase_run.id)
    assert {:ok, snapshot} = Persistence.fetch_phase_evidence_snapshot(phase.id)
    assert Enum.count(snapshot.evidence.comparisons) == 6
    assert {:ok, plan} = Persistence.Collection.fetch_collection_plan(phase_run.id)
    assert Enum.count(plan.items) == 9
    assert {:ok, rows} = Persistence.Collection.list_replica_items(phase_run.id, 0)
    assert Enum.all?(rows, &(is_binary(&1.optimization_run_id) and is_binary(&1.experiment_id)))
    assert Enum.count(Enum.uniq_by(rows, & &1.optimization_run_id)) == 9
    assert Enum.count(Enum.uniq_by(rows, & &1.experiment_id)) == 9
    assert {:ok, stored_revision} = Persistence.fetch_revision(revision)
    assert Enum.count(Definition.collection_groups(stored_revision.definition)) == 9
    assert {:ok, same} = Workflow.ensure_pilot_collection_run(phase.id)
    assert same.id == phase_run.id
    # Collection completion remains separate from Goal 03's phase acceptance.
    assert {:ok, %{state: :collecting_pilot}} = Study.status(execution.id)
  end
end
