defmodule NetworkDefense.Evaluation.Study.StudyPilotSnapshotTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Study.Collection
  alias NetworkDefense.Evaluation.Study.CollectionItems
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.PilotSnapshot
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyFixtures, StudyPhase}
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, Experiments, MissionImpact, Run, Seed}

  setup do
    study = StudyFixtures.study_with_two_phases()
    collection = StudyFixtures.insert_collection_graph("study-pilot-snapshot", mission: true)
    definition = StudyFixtures.collection_definition(collection.graph, collection.foothold)

    study
    |> Map.merge(collection)
    |> Map.put(:definition, definition)
  end

  test "PILOT-SNAPSHOT-01: fan-in stores one aligned snapshot in declared order", context do
    items = collected(context)
    pairs = Enum.zip(work(context), items)

    assert {:ok, snapshot_id} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert {:ok, snapshot, payload} = EvidenceSnapshots.load(snapshot_id)

    assert snapshot.phase == :pilot
    assert snapshot.schema_version == context.definition.schema_version
    assert snapshot.family_id == context.definition.family.id
    assert snapshot.study_revision_id == context.execution.study_revision_id

    assert %StudyPhase{snapshot_id: ^snapshot_id} = Repo.get(StudyPhase, context.pilot_phase.id)

    assert [comparison] = payload.comparisons
    assert comparison.position == 0

    identity = comparison.identity

    assert {identity.tier, identity.budget, identity.alternative, identity.reference,
            identity.outcome} == {"core", 1, "null", "cvss", "mission_impact"}

    evidence = comparison.evidence
    assert evidence.outcome == "mission_impact"
    assert evidence.alternative.strategy == "null"
    assert evidence.reference.strategy == "cvss"

    assert Enum.map(evidence.alternative.plans, & &1.id) == plan_ids(pairs, :alternative)
    assert Enum.map(evidence.reference.plans, & &1.id) == plan_ids(pairs, :reference)

    assert evidence.attack_seeds == attack_seeds(hd(items))
    assert Enum.count(evidence.attack_seeds) == 10

    for {work_item, item} <- pairs do
      plan = plan_row(evidence, work_item)

      assert plan.mission_impacts == mission_impacts(item)
      assert Enum.count(plan.mission_impacts) == Enum.count(evidence.attack_seeds)
      assert Enum.all?(plan.mission_impacts, &(&1 > 0))
    end

    provenance = comparison.provenance

    expected_revisions =
      Enum.uniq([declared_revision(context.definition) | output_revision_ids(items)])

    assert provenance.graph_revision_ids == expected_revisions
    assert provenance.model_revision == context.definition.study.revisions.model
    assert provenance.collection_seed == 310_001
    assert provenance.environment == context.definition.study.revisions.environment

    assert provenance.source_run_ids ==
             Enum.flat_map(items, &[&1.optimization_run_id, &1.experiment_id])

    runtime = payload.runtime_evidence
    assert runtime.tier_count == 1
    assert runtime.strategy_group_count == 2
    assert runtime.plan_selection_ms == plan_selection_ms(items)
    assert runtime.attack_trial_ms == attack_trial_ms(items)
    assert Enum.count(runtime.attack_trial_ms) == 100
  end

  test "PILOT-SNAPSHOT-02: a zero-millisecond plan duration is preserved", context do
    items = collected(context)
    set_optimization_runtime(items, 0)

    assert {:ok, snapshot_id} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert {:ok, _snapshot, payload} = EvidenceSnapshots.load(snapshot_id)

    assert payload.runtime_evidence.plan_selection_ms == List.duplicate(0.0, 10)
    assert Enum.all?(payload.runtime_evidence.plan_selection_ms, &is_float/1)
  end

  test "PILOT-SNAPSHOT-03: a missing, duplicated, foreign, or replicated item set is rejected",
       context do
    items = collected(context)
    count = snapshot_count()

    {:ok, foreign} = CollectionItems.get_or_create(context.final_phase.id, 0, 9)
    {:ok, replicated} = CollectionItems.get_or_create(context.pilot_phase.id, 1, 9)

    rejected_sets = [
      Enum.drop(items, -1),
      items ++ [Enum.at(items, -1)],
      List.replace_at(items, -1, foreign),
      List.replace_at(items, -1, replicated),
      [%StudyCollectionItem{} | items],
      [%{hd(items) | id: "not-a-uuid"} | tl(items)],
      [%{hd(items) | id: nil} | tl(items)],
      [:not_a_collection_item | tl(items)]
    ]

    for rejected <- rejected_sets do
      assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
               PilotSnapshot.assemble_and_store_pilot_snapshot(
                 context.pilot_phase,
                 rejected,
                 context.definition
               )

      assert issue["code"] == "incomplete_pilot_evidence"
    end

    assert snapshot_count() == count
    assert %StudyPhase{snapshot_id: nil} = Repo.get(StudyPhase, context.pilot_phase.id)
  end

  test "PILOT-SNAPSHOT-04: an unlinked experiment is rejected", context do
    items = collected(context)
    item = Enum.at(items, -1)
    unlink_experiment(item)

    assert {:error, %StudyError{issues: [issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert issue["code"] == "incomplete_pilot_evidence"
    assert issue["path"] == ["collection_items", item.item_position, "experiment_id"]
    assert snapshot_count() == 0
  end

  test "PILOT-SNAPSHOT-05: an unfinished experiment and an unfinished optimization are rejected",
       context do
    items = collected(context)
    item = Enum.at(items, -1)

    set_experiment_status(item, :running)

    assert {:error, %StudyError{issues: [experiment_issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert experiment_issue["path"] == ["collection_items", item.item_position, "experiment_id"]

    set_experiment_status(item, :completed)
    set_optimization_status(item, "failed")

    assert {:error, %StudyError{issues: [optimization_issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert optimization_issue["path"] ==
             ["collection_items", item.item_position, "optimization_run_id"]

    set_optimization_status(item, "completed")
    alternative_item = hd(items)
    set_optimization_strategy(alternative_item, "cvss")

    assert {:error, %StudyError{issues: [identity_issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert identity_issue["path"] ==
             ["collection_items", alternative_item.item_position, "optimization_run_id"]

    assert snapshot_count() == 0
  end

  test "PILOT-SNAPSHOT-06: a legacy trial without a measured runtime is rejected", context do
    items = collected(context)
    item = Enum.at(items, -1)
    set_trial_runtime(item, nil)

    assert {:error, %StudyError{issues: [issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert issue["code"] == "incomplete_pilot_evidence"
    assert issue["path"] == ["collection_items", item.item_position, "runtime_us"]
    assert snapshot_count() == 0
  end

  test "PILOT-SNAPSHOT-07: a repeated checkpoint returns the same linked snapshot", context do
    items = collected(context)
    count = snapshot_count()

    assert {:ok, snapshot_id} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    set_experiment_status(Enum.at(items, -1), :running)

    assert {:ok, repeated_id} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert repeated_id == snapshot_id
    assert snapshot_count() == count + 1
    assert %StudyPhase{snapshot_id: ^snapshot_id} = Repo.get(StudyPhase, context.pilot_phase.id)
  end

  test "PILOT-SNAPSHOT-08: a trial seed that is not the derived child seed is rejected",
       context do
    items = collected(context)
    item = Enum.at(items, -1)
    experiment = Experiments.load(item.experiment_id)
    stored = Enum.find(experiment.runs, &(&1.trial_index == 1))
    set_trial_seed(item, stored.seed + 1)

    assert {:error, %StudyError{issues: [issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert issue["code"] == "incomplete_pilot_evidence"
    assert issue["path"] == ["collection_items", item.item_position, "seed"]
    assert snapshot_count() == 0
  end

  test "PILOT-SNAPSHOT-09: an experiment that ran on another graph revision is rejected",
       context do
    items = collected(context)
    item = hd(items)
    swapped = completed_experiment_on_another_graph()
    link_experiment(item, swapped.id)

    assert {:error, %StudyError{issues: [issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               items,
               context.definition
             )

    assert issue["code"] == "incomplete_pilot_evidence"
    assert issue["path"] == ["collection_items", item.item_position, "experiment_id"]
    assert snapshot_count() == 0
  end

  test "PILOT-SNAPSHOT-10: the persisted phase owns the checkpoint", context do
    items = collected(context)
    count = snapshot_count()
    forged = %{context.pilot_phase | id: Ecto.UUID.generate()}

    assert {:error, %StudyError{issues: [forged_issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               forged,
               items,
               context.definition
             )

    assert forged_issue["code"] == "invalid_study_phase"

    assert {:error, %StudyError{issues: [phase_issue]}} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.final_phase,
               items,
               context.definition
             )

    assert phase_issue["code"] == "unsupported_collection_phase"

    stale = %{
      context.pilot_phase
      | phase: :final_collection,
        snapshot_id: Ecto.UUID.generate()
    }

    assert {:ok, snapshot_id} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               stale,
               items,
               context.definition
             )

    assert %StudyPhase{snapshot_id: ^snapshot_id} = Repo.get(StudyPhase, context.pilot_phase.id)
    assert snapshot_count() == count + 1
  end

  test "PILOT-SNAPSHOT-11: stale or forged item links do not become evidence", context do
    items = collected(context)
    first = hd(items)
    second = Enum.at(items, 1)

    forged_items = [
      %{first | optimization_run_id: second.optimization_run_id, experiment_id: nil}
      | tl(items)
    ]

    assert {:ok, snapshot_id} =
             PilotSnapshot.assemble_and_store_pilot_snapshot(
               context.pilot_phase,
               forged_items,
               context.definition
             )

    assert {:ok, _snapshot, payload} = EvidenceSnapshots.load(snapshot_id)
    [comparison] = payload.comparisons

    expected_ids =
      work(context)
      |> Enum.filter(&(&1.side == :alternative))
      |> Enum.sort_by(& &1.plan_position)
      |> Enum.map(&Enum.at(items, &1.item_position).optimization_run_id)

    assert Enum.map(comparison.evidence.alternative.plans, & &1.id) == expected_ids
    assert hd(expected_ids) == first.optimization_run_id
    assert hd(expected_ids) != second.optimization_run_id
  end

  defp collected(context) do
    StudyFixtures.collect_pilot_items(context.execution, context.pilot_phase, context.definition)
  end

  defp work(context) do
    {:ok, work} =
      Collection.build_collection_work(
        context.execution,
        context.pilot_phase,
        context.definition,
        0
      )

    work
  end

  defp declared_revision(definition), do: hd(definition.graphs).graph_revision_id

  defp plan_ids(pairs, side) do
    pairs
    |> Enum.filter(fn {work_item, _item} -> work_item.side == side end)
    |> Enum.map(fn {_work_item, item} -> item.optimization_run_id end)
  end

  defp plan_row(evidence, work_item) do
    side =
      case work_item.side do
        :alternative -> evidence.alternative
        :reference -> evidence.reference
      end

    Enum.at(side.plans, work_item.plan_position)
  end

  defp attack_seeds(item), do: item |> runs() |> Enum.map(& &1.seed)

  defp runs(item) do
    %Experiment{runs: runs} = Experiments.load(item.experiment_id)
    Enum.sort_by(runs, & &1.trial_index)
  end

  defp mission_impacts(item) do
    optimization = Repo.get!(OptimizationRun, item.optimization_run_id)
    graph = Graphs.load_revision(optimization.output_graph_revision_id)

    item
    |> runs()
    |> Enum.map(fn run ->
      run
      |> Run.current_attacker_state()
      |> AttackerState.foothold_nodes()
      |> then(&MissionImpact.final(graph, &1))
    end)
  end

  defp output_revision_ids(items) do
    Enum.map(items, &optimization(&1).output_graph_revision_id)
  end

  defp plan_selection_ms(items) do
    Enum.map(items, &(optimization(&1).runtime_ms * 1.0))
  end

  defp attack_trial_ms(items) do
    Enum.flat_map(items, fn item -> Enum.map(runs(item), fn run -> run.runtime_us / 1000 end) end)
  end

  defp optimization(item), do: Repo.get!(OptimizationRun, item.optimization_run_id)

  defp set_optimization_runtime(items, value) do
    ids = Enum.map(items, & &1.optimization_run_id)

    Repo.update_all(from(run in OptimizationRun, where: run.id in ^ids), set: [runtime_ms: value])
  end

  defp set_optimization_status(item, status) do
    Repo.update_all(
      from(run in OptimizationRun, where: run.id == ^item.optimization_run_id),
      set: [status: status]
    )
  end

  defp set_optimization_strategy(item, strategy) do
    Repo.update_all(
      from(run in OptimizationRun, where: run.id == ^item.optimization_run_id),
      set: [strategy: strategy]
    )
  end

  defp set_trial_seed(item, seed) do
    Repo.update_all(
      from(run in Run,
        where: run.experiment_id == ^item.experiment_id and run.trial_index == 1
      ),
      set: [seed: seed]
    )
  end

  defp set_experiment_status(item, status) do
    Repo.update_all(
      from(experiment in Experiment, where: experiment.id == ^item.experiment_id),
      set: [status: status]
    )
  end

  defp set_trial_runtime(item, value) do
    Repo.update_all(
      from(run in Run, where: run.experiment_id == ^item.experiment_id),
      set: [runtime_us: value]
    )
  end

  defp unlink_experiment(item) do
    Repo.update_all(
      from(collection_item in StudyCollectionItem, where: collection_item.id == ^item.id),
      set: [experiment_id: nil]
    )
  end

  defp link_experiment(item, experiment_id) do
    item
    |> StudyCollectionItem.link_changeset(%{experiment_id: experiment_id})
    |> Repo.update!()
  end

  defp completed_experiment_on_another_graph do
    other = StudyFixtures.insert_collection_graph("pilot-snapshot-other", mission: true)

    {:ok, experiment} =
      Experiment.new(
        graph: other.graph,
        master_seed: 310_001,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 10,
        initial_foothold_node_id: other.foothold.id
      )
      |> Experiments.create()

    runs =
      for index <- 1..10 do
        Run.new(
          graph: other.graph,
          experiment_id: experiment.id,
          trial_index: index,
          seed: Seed.child_seed(310_001, index),
          runtime_us: 10,
          initial_attacker_state: AttackerState.new(other.foothold.id)
        )
      end

    {:ok, completed} = Experiments.complete_with_runs(experiment, runs, 5)
    completed
  end

  defp snapshot_count, do: Repo.aggregate(EvidenceSnapshot, :count)
end
