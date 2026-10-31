defmodule NetworkDefense.Evaluation2.FinalCollectionTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Evaluation2.Study.{Collection, Persistence, Randomness, Tier}
  alias NetworkDefense.Evaluation2.Study.Final.Collection, as: FinalCollection
  alias NetworkDefense.Evaluation2.Study.Final.TierRun
  alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: Store
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Replica
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Tier, as: TimingTier
  alias NetworkDefense.Evaluation2Test.FinalFixtures
  alias NetworkDefense.Optimization.{OptimizationRun, OptimizationRuns}
  alias NetworkDefense.Simulation.{Experiment, Experiments, IterationStep}

  @moduletag :integration
  @moduletag case_id: "COL-01/COL-03/COL-04/TIME-04"

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    context = FinalFixtures.approved_context()
    {:ok, dag} = Gust.Flows.create_dag(%{name: "final_collection_fixture"})

    tier_runs =
      for tier <- Tier.all() do
        id = Ecto.UUID.generate()

        {:ok, run} =
          Gust.Flows.create_run(%{dag_id: dag.id, params: %{"study_phase_run_id" => id}})

        {:ok, phase_run} = Persistence.link_phase_run(context.active_phase.id, tier, id, run.id)

        {:ok, plan} =
          Collection.prepare_final(
            id,
            context.revision.definition,
            context.execution.selection,
            tier
          )

        for position <- -1..4 do
          {:ok, items} = Collection.prepare_replica(plan.id, position)

          for item <- items do
            :ok = Collection.run_optimization(item.id)
            :ok = Collection.run_simulation(item.id)
          end
        end

        %TierRun{
          tier: tier,
          phase_run_id: phase_run.id,
          gust_run_id: run.id,
          clock_session: "session-#{tier}",
          timing: timing()
        }
      end

    %{context: context, tiers: tier_runs}
  end

  test "COL-03/RNG-02 WHEN Final replicas repeat seeds THEN each SHALL own fresh effects", c do
    first = hd(c.tiers)
    {:ok, plan} = Store.fetch_collection_plan(first.phase_run_id)
    assert Enum.map(plan.items, &{&1.group_position, &1.plan_position}) == [{0, 0}, {1, 0}]

    assert Enum.all?(
             plan.items,
             &(&1.selection_seed ==
                 Randomness.selection_seed(c.context.revision.definition, :final, 0))
           )

    batches =
      for replica <- -1..4 do
        {:ok, items} = Store.list_replica_items(first.phase_run_id, replica)
        assert [_first, _second] = items
        items
      end

    items = List.flatten(batches)
    assert Enum.count(Enum.uniq_by(items, & &1.id)) == 12
    assert Enum.count(Enum.uniq_by(items, & &1.optimization_run_id)) == 12
    assert Enum.count(Enum.uniq_by(items, & &1.experiment_id)) == 12

    assert Enum.uniq(Enum.map(items, &Repo.get!(OptimizationRun, &1.optimization_run_id).seed)) ==
             [Randomness.selection_seed(c.context.revision.definition, :final, 0)]

    assert Enum.uniq(Enum.map(items, &Repo.get!(Experiment, &1.experiment_id).master_seed)) == [
             Randomness.evaluation_root(c.context.revision.definition, :final, :small)
           ]
  end

  test "TIME-04/COL-04 WHEN only execution artifacts differ THEN Final snapshot preparation SHALL pass without acceptance",
       c do
    assert {:ok, snapshot, timings} =
             FinalCollection.prepare_snapshot(c.tiers, c.context.execution)

    assert [_small, _medium, _large] = snapshot.evidence.comparisons
    assert Map.keys(timings.by_tier) |> Enum.sort() == [:large, :medium, :small]

    assert {:ok, %{execution: %{state: :collecting_final}}} =
             Persistence.Executions.fetch_context(c.context.execution.id)

    assert {:error, _} =
             Persistence.fetch_execution_phase(c.context.execution.id, :final_analysis)

    assert {:ok, same, ^timings} = FinalCollection.prepare_snapshot(c.tiers, c.context.execution)
    assert same.id == snapshot.id

    assert {:ok, accepted} =
             Persistence.Executions.accept_final_collection(c.context.active_phase.id)

    assert accepted.execution.state == :analyzing_final
    assert accepted.active_phase.phase == :final_analysis
  end

  test "TIME-04 WHEN a required attacker outcome changes with equal mission impact THEN equality SHALL fail",
       c do
    {:ok, items} = Store.list_replica_items(hd(c.tiers).phase_run_id, 2)
    [trial | _] = Experiments.load(hd(items).experiment_id).runs
    state = %{credential_ids: [Ecto.UUID.generate()]}

    Repo.update!(
      Ecto.Changeset.change(trial)
      |> Ecto.Changeset.put_embed(:initial_attacker_state, state)
    )

    assert {:error, failure} = FinalCollection.prepare_snapshot(c.tiers, c.context.execution)
    assert Enum.any?(failure.issues, &(&1.code == "unequal_final_replicas"))
    assert {:error, _} = Persistence.fetch_phase_evidence_snapshot(c.context.active_phase.id)
  end

  test "TIME-04 WHEN a selected action target changes THEN equality SHALL fail", c do
    {:ok, items} = Store.list_replica_items(hd(c.tiers).phase_run_id, 1)

    optimization =
      OptimizationRuns.load(hd(items).optimization_run_id)

    [action | _] = optimization.actions
    Repo.update!(Ecto.Changeset.change(action, target_id: Ecto.UUID.generate()))
    assert {:error, _} = FinalCollection.prepare_snapshot(c.tiers, c.context.execution)
  end

  test "COL-04 WHEN a source trial is absent THEN Final snapshot preparation SHALL fail", c do
    {:ok, items} = Store.list_replica_items(hd(c.tiers).phase_run_id, 4)
    [trial | _] = Experiments.load(hd(items).experiment_id).runs
    Repo.delete_all(from(step in IterationStep, where: step.run_id == ^trial.id))
    Repo.delete!(trial)
    assert {:error, _} = FinalCollection.prepare_snapshot(c.tiers, c.context.execution)
  end

  defp timing do
    %TimingTier{
      replicas:
        Map.new(0..4, fn position ->
          {position,
           %Replica{plan_selection_us: 10 + position, simulation_us: 20, total_us: 30 + position}}
        end)
    }
  end
end
