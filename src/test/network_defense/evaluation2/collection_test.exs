defmodule NetworkDefense.Evaluation2.CollectionTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  alias NetworkDefense.Evaluation2.Study.{
    Collection,
    Definition,
    Persistence,
    Randomness,
    Revision
  }

  alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: Store
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2.Study.Pilot.Analysis
  alias NetworkDefense.Evaluation2Test.{FoundationFixtures, GraphFixtures}
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Simulation.{Experiment, Run, Seed}

  @moduletag :integration

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)
    tiers = GraphFixtures.insert_tiers()
    attrs = FoundationFixtures.valid_attrs(GraphFixtures.document_opts(tiers))

    attrs =
      put_in(attrs, ["pilot", "candidates"], [%{"id" => "tiny", "plans" => 2, "attacks" => 2}])

    attrs = put_in(attrs, ["pilot", "extra_pool"], %{"plans" => 0, "attacks" => 0})
    attrs = put_in(attrs, ["simulation", "iterations_per_run"], 2)
    attrs = put_in(attrs, ["defense", "feasibility"], "unrestricted")

    attrs =
      update_in(attrs, ["tiers"], fn tiers ->
        Map.new(tiers, fn {tier, value} ->
          {tier,
           %{
             value
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

    {:ok, parsed} = Definition.parse(attrs)
    {:ok, definition} = Definition.resolve(parsed)
    {:ok, revision} = Persistence.insert_revision(definition)

    identity = %NetworkDefense.Evaluation2.Study.Revision{
      study_id: revision.study_id,
      revision: revision.revision
    }

    {:ok, context} = Executions.start_execution(identity)
    phase_run_id = Ecto.UUID.generate()

    {:ok, dag} =
      Gust.Flows.create_dag(%{name: "evaluation2_study_pilot_collection"})

    {:ok, gust_run} =
      Gust.Flows.create_run(%{dag_id: dag.id, params: %{"study_phase_run_id" => phase_run_id}})

    {:ok, phase_run} =
      Persistence.link_phase_run(context.active_phase.id, :single, phase_run_id, gust_run.id)

    {:ok, plan} = Collection.prepare_pilot(phase_run.id, definition)
    {:ok, items} = Collection.prepare_replica(plan.id, 0)

    %{
      definition: definition,
      phase_id: context.active_phase.id,
      phase_run: phase_run,
      plan: plan,
      items: items
    }
  end

  @tag case_id: "COL-01"
  test "WHEN two alternatives share a budget THEN one CVSS group owns each physical row", c do
    assert Enum.count(c.plan.items) == 18
    assert Enum.count(c.items) == 18
    assert Enum.map(c.items, & &1.item_position) == Enum.to_list(0..17)

    assert Enum.map(c.plan.items, &{&1.group_position, &1.plan_position}) ==
             for(group <- 0..8, row <- 0..1, do: {group, row})

    assert Enum.map(c.plan.items, & &1.strategy.key) ==
             List.flatten(
               List.duplicate(
                 [:cvss, :cvss, :random, :random, :simulation_informed, :simulation_informed],
                 3
               )
             )

    assert {:ok, again} = Collection.prepare_pilot(c.phase_run.id, c.definition)
    assert again == c.plan
    assert {:ok, stored} = Store.fetch_collection_plan(c.phase_run.id)
    assert stored.items == c.plan.items
    assert {:ok, same_items} = Collection.prepare_replica(c.plan.id, 0)
    assert Enum.map(same_items, & &1.id) == Enum.map(c.items, & &1.id)

    for work <- c.plan.items do
      assert work.simulation == c.definition.simulation
      assert work.require_pre_attack_feasibility == false

      assert work.selection_seed ==
               Randomness.selection_seed(c.definition, :pilot, work.plan_position)

      assert work.candidate_action_types ==
               Definition.effective_action_types(c.definition, work.strategy.key)
    end
  end

  @tag case_id: "POLICY-01"
  test "WHEN requests are reserved THEN scoring and evidence inherit the same model and feasibility",
       c do
    simple = hd(c.items)
    scored = Enum.at(c.items, 4)
    assert {:ok, simple_run} = Store.reserve_optimization(simple.id)
    assert simple_run.execution_config.scoring == nil
    assert simple_run.execution_config.candidate_action_types == [:patch_vulnerability]
    assert {:ok, scored_run} = Store.reserve_optimization(scored.id)
    scoring = scored_run.execution_config.scoring
    assert scoring.iterations_per_run == 2
    assert scoring.max_attempts == c.definition.simulation.max_attempts
    assert scoring.rules == c.definition.simulation.rules
    assert scoring.monte_carlo_trials == 1
    assert scored_run.execution_config.require_pre_attack_feasibility == false
    assert :ok = Collection.run_optimization(scored.id)
    assert {:ok, experiment} = Store.reserve_experiment(scored.id)
    assert experiment.iteration_count == scoring.iterations_per_run
    assert experiment.max_attempts == scoring.max_attempts
    assert experiment.rules == scoring.rules
    assert experiment.require_pre_attack_feasibility == false
  end

  @tag case_id: "COL-02"
  test "WHEN effects retry THEN their item keeps both canonical links", c do
    item = hd(c.items)
    assert {:ok, _reserved} = Store.reserve_optimization(item.id)
    assert :ok = Collection.run_optimization(item.id)
    first = Repo.get!(Persistence.CollectionItem, item.id)
    assert is_binary(first.optimization_run_id)
    assert :ok = Collection.run_optimization(item.id)

    assert Repo.get!(Persistence.CollectionItem, item.id).optimization_run_id ==
             first.optimization_run_id

    assert :ok = Collection.run_simulation(item.id)
    second = Repo.get!(Persistence.CollectionItem, item.id)
    assert is_binary(second.experiment_id)
    assert :ok = Collection.run_simulation(item.id)
    assert Repo.get!(Persistence.CollectionItem, item.id).experiment_id == second.experiment_id
    assert {:ok, reserved} = Store.reserve_optimization(item.id)
    assert reserved.id == first.optimization_run_id
    assert {:ok, experiment} = Store.reserve_experiment(item.id)
    assert experiment.id == second.experiment_id
  end

  @tag case_id: "COL-03"
  @tag case_id_rng: "RNG-02"
  test "WHEN another replica repeats inputs THEN it owns fresh effects and the same seeds", c do
    {:ok, replica} = Collection.prepare_replica(c.plan.id, 1)
    a = hd(c.items)
    b = hd(replica)
    refute a.id == b.id

    for item <- [a, b] do
      assert :ok = Collection.run_optimization(item.id)
      assert :ok = Collection.run_simulation(item.id)
    end

    a = Repo.get!(Persistence.CollectionItem, a.id)
    b = Repo.get!(Persistence.CollectionItem, b.id)
    refute a.optimization_run_id == b.optimization_run_id
    refute a.experiment_id == b.experiment_id

    assert Repo.get!(OptimizationRun, a.optimization_run_id).seed ==
             Repo.get!(OptimizationRun, b.optimization_run_id).seed

    assert Repo.get!(Experiment, a.experiment_id).master_seed ==
             Repo.get!(Experiment, b.experiment_id).master_seed
  end

  @tag case_id: "COL-03"
  @tag case_id_rng: "RNG-02"
  test "WHEN another phase collects the same revision THEN scientific requests repeat with fresh effects",
       c do
    identity = %Revision{study_id: "example-study", revision: 1}
    assert {:ok, context} = Executions.start_execution(identity)
    id = Ecto.UUID.generate()
    dag_id = Gust.Flows.get_run!(c.phase_run.gust_run_id).dag_id

    assert {:ok, run} =
             Gust.Flows.create_run(%{dag_id: dag_id, params: %{"study_phase_run_id" => id}})

    assert {:ok, phase_run} =
             Persistence.link_phase_run(context.active_phase.id, :single, id, run.id)

    assert {:ok, plan} = Collection.prepare_pilot(phase_run.id, c.definition)
    assert plan.items == c.plan.items
    assert {:ok, items} = Collection.prepare_replica(plan.id, 0)
    first = hd(c.items)
    second = hd(items)
    refute first.id == second.id

    for item <- [first, second] do
      assert :ok = Collection.run_optimization(item.id)
      assert :ok = Collection.run_simulation(item.id)
    end

    first = Repo.get!(Persistence.CollectionItem, first.id)
    second = Repo.get!(Persistence.CollectionItem, second.id)
    refute first.optimization_run_id == second.optimization_run_id
    refute first.experiment_id == second.experiment_id
  end

  @tag case_id: "COL-03"
  test "WHEN another phase repeats the configuration THEN its items own fresh effects", c do
    identity = %NetworkDefense.Evaluation2.Study.Revision{
      study_id: c.definition.study.id,
      revision: c.definition.study.revision
    }

    {:ok, context} = Executions.start_execution(identity)
    run = Gust.Repo.get!(Gust.Flows.Run, c.phase_run.gust_run_id)
    id = Ecto.UUID.generate()

    {:ok, gust_run} =
      Gust.Flows.create_run(%{dag_id: run.dag_id, params: %{"study_phase_run_id" => id}})

    {:ok, phase_run} =
      Persistence.link_phase_run(context.active_phase.id, :single, id, gust_run.id)

    {:ok, plan} = Collection.prepare_pilot(phase_run.id, c.definition)
    assert plan.items == c.plan.items
    {:ok, fresh} = Collection.prepare_replica(plan.id, 0)
    [first, second] = [hd(c.items), hd(fresh)]

    for item <- [first, second] do
      assert :ok = Collection.run_optimization(item.id)
      assert :ok = Collection.run_simulation(item.id)
    end

    first = Repo.get!(Persistence.CollectionItem, first.id)
    second = Repo.get!(Persistence.CollectionItem, second.id)
    refute first.id == second.id
    refute first.optimization_run_id == second.optimization_run_id
    refute first.experiment_id == second.experiment_id
  end

  @tag case_id: "COL-04"
  test "WHEN observations complete THEN comparisons project shared CVSS matrices and aligned attack columns",
       c do
    for item <- c.items do
      assert :ok = Collection.run_optimization(item.id)
      assert :ok = Collection.run_simulation(item.id)
    end

    assert {:ok, snapshot} = Collection.assemble_evidence(c.phase_id)
    comparisons = snapshot.evidence.comparisons
    assert Enum.count(comparisons) == 6

    for {[a, b], tier} <- Enum.zip(Enum.chunk_every(comparisons, 2), c.definition.tiers) do
      assert a.reference == b.reference
      assert a.attack_seeds == b.attack_seeds

      assert a.attack_seeds ==
               for(
                 i <- 1..2,
                 do:
                   Seed.child_seed(Randomness.evaluation_root(c.definition, :pilot, tier.tier), i)
               )

      for matrix <- [a.alternative, b.alternative, a.reference] do
        assert Enum.count(matrix) == 2

        for row <- matrix do
          assert Enum.count(row) == 2
          assert Enum.all?(row, &(&1 >= 0 and &1 <= tier.mission_impact_bound.maximum))
        end
      end
    end

    assert {:ok, same} = Collection.assemble_evidence(c.phase_id)
    assert same.id == snapshot.id
    assert {:ok, jobs} = Analysis.prepare(snapshot.id)

    assert Enum.map(jobs, & &1.stream_seed) ==
             Enum.map(
               Definition.comparisons(c.definition),
               &Randomness.pilot_planning_seed(c.definition, &1)
             )

    # Source bindings must hold even after a snapshot already exists.
    first = Repo.get!(Persistence.CollectionItem, hd(c.items).id)
    optimization = Repo.get!(OptimizationRun, first.optimization_run_id)
    Repo.update!(Ecto.Changeset.change(optimization, seed: optimization.seed + 1))
    assert {:error, _} = Collection.assemble_evidence(c.phase_id)

    Repo.update!(
      Ecto.Changeset.force_change(Ecto.Changeset.change(optimization), :seed, optimization.seed)
    )

    experiment = Repo.get!(Experiment, first.experiment_id)
    Repo.update!(Ecto.Changeset.change(experiment, max_attempts: experiment.max_attempts + 1))
    assert {:error, _} = Collection.assemble_evidence(c.phase_id)

    Repo.update!(
      Ecto.Changeset.force_change(
        Ecto.Changeset.change(experiment),
        :max_attempts,
        experiment.max_attempts
      )
    )

    run =
      Repo.one!(
        from r in Run, where: r.experiment_id == ^first.experiment_id and r.trial_index == 1
      )

    Repo.update!(Ecto.Changeset.change(run, seed: run.seed + 1))

    assert {:error, %{issues: [%{code: "incomplete_collection_evidence"}]}} =
             Collection.assemble_evidence(c.phase_id)
  end

  @tag case_id: "BIND-02"
  test "WHEN completion artifacts are read THEN canonical input and terminal success remain required",
       c do
    alias NetworkDefense.Evaluation2.Study.Workflow
    run = Gust.Repo.get!(Gust.Flows.Run, c.phase_run.gust_run_id)
    assert {:error, _} = Workflow.pilot_collection_result(c.phase_run.id)
    run = Gust.Repo.update!(Ecto.Changeset.change(run, status: :succeeded))
    assert {:error, _} = Workflow.pilot_collection_result(c.phase_run.id)

    {:ok, terminal} =
      Gust.Flows.create_task(%{
        run_id: run.id,
        name: "complete_pilot_collection",
        status: :succeeded,
        result: %{}
      })

    assert {:ok, %NetworkDefense.Evaluation2.Study.Pilot.CollectionContract.Output{}} =
             Workflow.pilot_collection_result(c.phase_run.id)

    Gust.Repo.update!(
      Ecto.Changeset.change(run, params: %{"study_phase_run_id" => Ecto.UUID.generate()})
    )

    assert {:error, _} = Workflow.pilot_collection_result(c.phase_run.id)

    Gust.Repo.update!(
      Ecto.Changeset.force_change(Ecto.Changeset.change(run), :params, %{
        "study_phase_run_id" => c.phase_run.id
      })
    )

    Gust.Repo.update!(Ecto.Changeset.change(terminal, status: :failed))
    assert {:error, _} = Workflow.pilot_collection_result(c.phase_run.id)
  end

  @tag case_id: "COL-04"
  test "WHEN effects or rows are incomplete THEN assembly fails before storing evidence", c do
    assert {:error, _} = Collection.assemble_evidence(c.phase_id)
    assert Repo.aggregate(Persistence.EvidenceSnapshot, :count) == 0
  end
end
