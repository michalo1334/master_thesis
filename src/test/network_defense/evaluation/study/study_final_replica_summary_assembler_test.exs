defmodule NetworkDefense.Evaluation.Study.FinalReplicaSummaryAssemblerTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias NetworkDefense.Actions.{AttemptedAction, ExploitVulnerability}
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.FinalReplicaSummaryAssembler
  alias NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary

  alias NetworkDefense.Evaluation.Study.Timing.FinalReplicaSummary.{
    CapabilityStatus,
    Foothold,
    Item,
    RequiredFlowStatus,
    Trial
  }

  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyFixtures}
  alias NetworkDefense.Graph.Contracts.{Edge, Node}
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.MissionCapability
  alias NetworkDefense.Optimization.{OptimizationAction, OptimizationRun}
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, IterationStep, Run}

  setup do
    final_context("study-final-assembler", mission: true)
  end

  defp final_context(title, opts) do
    collection = StudyFixtures.insert_collection_graph(title, opts)
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

    items = StudyFixtures.collect_pilot_items(execution, study.final_phase, definition, 0)

    Map.merge(study, %{
      definition: definition,
      execution: execution,
      items: items,
      graph: collection.graph,
      foothold: collection.foothold,
      alternate_foothold: collection.alternate_foothold,
      required_flows: collection.required_flows
    })
  end

  test "C-06: WHEN every canonical work item holds one measured row, THE assembler SHALL return one typed complete-family summary",
       context do
    assert {:ok, %FinalReplicaSummary{} = summary, items} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    assert length(summary.items) == length(context.items)
    assert Enum.map(items, & &1.id) == Enum.map(context.items, & &1.id)
    assert Enum.map(items, & &1.item_position) == Enum.map(0..(length(items) - 1), & &1)

    summary.items
    |> Enum.with_index()
    |> Enum.each(fn {%Item{} = item, position} ->
      assert item.position == position
      assert is_integer(item.used_budget)
      assert item.selected_actions == plan_actions(context.items, position)
      assert Enum.map(item.trials, & &1.position) == Enum.map(0..9, & &1)
      assert Enum.map(item.trials, & &1.seed) == stored_seeds(context.items, position)

      # Display-only graph values are normalized; canonical identifiers stay.
      assert Enum.map(item.output_graph.nodes, & &1.id) ==
               context.graph |> Graph.nodes() |> Enum.map(& &1.id) |> Enum.sort()

      assert Enum.all?(item.output_graph.nodes, &canonical_view?/1)

      assert Enum.map(item.output_graph.edges, & &1.id) ==
               context.graph |> Graph.edges() |> Enum.map(& &1.id) |> Enum.sort()

      assert Enum.all?(
               item.pre_attack_capability_statuses,
               &match?(%{capability_id: id} when is_binary(id), &1)
             )

      assert Enum.map(item.pre_attack_capability_statuses, & &1.capability_id) ==
               Enum.sort(Enum.map(item.pre_attack_capability_statuses, & &1.capability_id))

      assert item.pre_attack_required_flow_statuses == []

      assert Enum.map(item.trials, &Enum.map(&1.steps, fn step -> step.index end)) ==
               stored_iteration_indexes(context.items, position)
    end)
  end

  test "C-06: WHEN stored rows carry attacker state and attempt data, THE assembler SHALL project the stored values",
       context do
    item = hd(context.items)
    run = first_run(item)
    service_id = Ecto.UUID.generate()
    vulnerability_node_id = Ecto.UUID.generate()

    initial_state = %AttackerState{
      foothold_ids: [context.foothold.id],
      credential_ids: [],
      privileges: %{context.foothold.id => "user"},
      attempted_actions: []
    }

    final_state = %AttackerState{
      foothold_ids: [context.alternate_foothold.id, context.foothold.id],
      credential_ids: ["credential-b", "credential-a"],
      privileges: %{
        context.foothold.id => "administrator",
        context.alternate_foothold.id => "user"
      },
      attempted_actions: []
    }

    attempted =
      %ExploitVulnerability{
        source_host_id: context.foothold.id,
        target_host_id: context.alternate_foothold.id,
        service_id: service_id,
        vulnerability_node_id: vulnerability_node_id,
        success_probability: 0.42,
        required_privilege: :user,
        granted_privilege: :administrator,
        supporting_edge_ids: ["edge-b", "edge-a"]
      }
      |> AttemptedAction.new()
      |> Map.put(:attempt_count, 2)

    run
    |> Ecto.Changeset.change(initial_attacker_state: Map.from_struct(initial_state))
    |> Repo.update!()

    %IterationStep{run_id: run.id}
    |> IterationStep.changeset(%{
      index: 1,
      success?: true,
      attempted_action: attempted,
      attacker_state: final_state
    })
    |> Repo.insert!()

    assert {:ok, %FinalReplicaSummary{} = summary, _items} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    %Item{trials: trials} = item_at(summary, item.item_position)
    trial = Enum.find(trials, &(&1.position == 0))
    assert %Trial{initial_state: projected_initial, final_state: projected_final} = trial

    assert projected_initial.footholds == [
             %Foothold{host_id: context.foothold.id, privilege: :user}
           ]

    assert projected_initial.credential_ids == []

    assert projected_final.footholds ==
             Enum.sort_by(
               [
                 %Foothold{host_id: context.foothold.id, privilege: :administrator},
                 %Foothold{host_id: context.alternate_foothold.id, privilege: :user}
               ],
               & &1.host_id
             )

    assert projected_final.credential_ids == ["credential-a", "credential-b"]

    assert [step] = trial.steps
    assert step.index == 1
    assert step.success? == true

    assert %{kind: :exploit_vulnerability} = step.action
    assert step.action.attempt_count == 2
    assert step.action.source_host_id == context.foothold.id
    assert step.action.target_host_id == context.alternate_foothold.id
    assert step.action.service_id == service_id
    assert step.action.vulnerability_node_id == vulnerability_node_id
    assert step.action.success_probability == 0.42
    assert step.action.required_privilege == :user
    assert step.action.granted_privilege == :administrator
    assert step.action.supporting_edge_ids == ["edge-a", "edge-b"]

    # Both supporting hosts are compromised in the stored final state, so every
    # mission capability is down in that state.
    capability_ids =
      context.graph
      |> Graph.nodes()
      |> Enum.filter(&(&1.type == MissionCapability))
      |> Enum.map(& &1.id)
      |> Enum.sort()

    assert Enum.map(trial.capability_outcomes, &{&1.capability_id, &1.down?}) ==
             Enum.map(capability_ids, &{&1, true})

    assert Enum.all?(item_at(summary, item.item_position).pre_attack_capability_statuses, fn
             %CapabilityStatus{down?: down?} -> down? == false
           end)
  end

  test "C-06: WHEN the stored graph declares required flows, THE assembler SHALL project each flow in canonical order" do
    context =
      final_context("study-final-assembler-flow", mission: true, required_flow: true)

    assert context.required_flows != []

    assert [_, _ | _] = context.required_flows

    assert {:ok, %FinalReplicaSummary{} = summary, _items} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    capability_id = capability_id(context.graph, "primary")

    expected =
      context.required_flows
      |> Enum.map(fn flow ->
        %RequiredFlowStatus{
          capability_id: capability_id,
          source_segment_id: flow["source_segment_id"],
          target_service_id: flow["target_service_id"],
          available?: true
        }
      end)
      |> Enum.sort_by(&{&1.capability_id, &1.source_segment_id, &1.target_service_id})

    [%Item{} = first | _rest] = summary.items
    assert first.pre_attack_required_flow_statuses == expected
  end

  test "C-06: WHEN two measured positions hold the same canonical work, THE assembler SHALL return equal summaries",
       context do
    _items =
      StudyFixtures.collect_pilot_items(
        context.execution,
        context.final_phase,
        context.definition,
        1
      )

    assert {:ok, zero, _items} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    assert {:ok, one, one_items} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 1)

    assert one == zero
    assert Enum.all?(one_items, &(&1.replica_position == 1))
  end

  test "C-07: WHEN one expected collection item is missing, THE assembler SHALL reject that measured position",
       context do
    [first | _rest] = context.items
    Repo.delete!(first)

    assert {:error, %StudyError{} = error} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    assert error == StudyError.final_replica_summary_invalid()
  end

  test "C-07: WHEN one extra collection item exists, THE assembler SHALL reject that measured position",
       context do
    %StudyCollectionItem{}
    |> StudyCollectionItem.create_changeset(%{
      study_phase_id: context.final_phase.id,
      replica_position: 0,
      item_position: length(context.items)
    })
    |> Repo.insert!()

    assert {:error, %StudyError{} = error} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    assert error == StudyError.final_replica_summary_invalid()
  end

  test "C-08: WHEN one stored optimization identity or setting differs from canonical work, THE assembler SHALL reject the summary",
       context do
    item = hd(context.items)
    run = Repo.get!(OptimizationRun, item.optimization_run_id)

    for change <- [%{seed: run.seed + 1}, %{status: "failed"}, %{requested_budget: 9}] do
      run |> Ecto.Changeset.change(change) |> Repo.update!()

      assert {:error, %StudyError{}} =
               FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0),
             "expected a rejected summary after #{inspect(change)}"

      run
      |> Ecto.Changeset.change(%{
        seed: run.seed,
        status: "completed",
        requested_budget: run.requested_budget
      })
      |> Repo.update!()
    end
  end

  test "C-08: WHEN the stored optimization action order is incomplete, THE assembler SHALL reject the summary",
       context do
    item = hd(context.items)
    run = Repo.get!(OptimizationRun, item.optimization_run_id)

    %OptimizationAction{}
    |> OptimizationAction.changeset(%{
      optimization_run_id: run.id,
      position: 99,
      action_type: "block_edge",
      target_id: Ecto.UUID.generate(),
      cost: 1
    })
    |> Repo.insert!()

    assert {:error, %StudyError{}} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)
  end

  test "C-08: WHEN one stored experiment identity, count, status, or seed differs from canonical work, THE assembler SHALL reject the summary",
       context do
    item = hd(context.items)
    experiment = Repo.get!(Experiment, item.experiment_id)

    for change <- [
          %{master_seed: experiment.master_seed + 1},
          %{status: :failed},
          %{iteration_count: experiment.iteration_count + 1}
        ] do
      experiment |> Ecto.Changeset.change(change) |> Repo.update!()

      assert {:error, %StudyError{}} =
               FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0),
             "expected a rejected summary after #{inspect(change)}"

      experiment
      |> Ecto.Changeset.change(%{
        master_seed: experiment.master_seed,
        status: :completed,
        iteration_count: experiment.iteration_count
      })
      |> Repo.update!()
    end
  end

  test "C-08: WHEN a stored experiment foothold differs from canonical work, THE assembler SHALL reject the summary",
       context do
    item = hd(context.items)
    experiment = Repo.get!(Experiment, item.experiment_id)

    assert experiment.initial_foothold_node_id == context.foothold.id

    experiment
    |> Ecto.Changeset.change(%{initial_foothold_node_id: context.alternate_foothold.id})
    |> Repo.update!()

    assert {:error, %StudyError{} = error} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    assert error == StudyError.final_replica_summary_invalid()
  end

  test "C-08: WHEN one stored trial count differs from canonical work, THE assembler SHALL reject the summary",
       context do
    item = hd(context.items)

    run =
      from(run in Run,
        where: run.experiment_id == ^item.experiment_id,
        order_by: [desc: run.trial_index],
        limit: 1
      )
      |> Repo.one!()

    Repo.delete!(run)

    assert {:error, %StudyError{}} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)
  end

  test "C-08: WHEN one stored simulation run order or seed differs, THE assembler SHALL reject the summary",
       context do
    item = hd(context.items)

    run =
      Repo.one!(
        from run in Run,
          where: run.experiment_id == ^item.experiment_id,
          order_by: run.trial_index,
          limit: 1
      )

    run |> Ecto.Changeset.change(%{trial_index: run.trial_index + 100}) |> Repo.update!()

    assert {:error, %StudyError{}} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)

    run |> Ecto.Changeset.change(%{trial_index: run.trial_index}) |> Repo.update!()

    run |> Ecto.Changeset.change(%{seed: run.seed + 1}) |> Repo.update!()

    assert {:error, %StudyError{}} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 0)
  end

  test "WHEN the phase is not a stored Final collection phase, THE assembler SHALL reject the request",
       context do
    assert {:error, %StudyError{} = error} =
             FinalReplicaSummaryAssembler.assemble(context.pilot_phase, context.definition, 0)

    assert error == StudyError.invalid_study_phase()
  end

  test "WHEN the measured position is outside 0..4, THE assembler SHALL reject the request",
       context do
    assert {:error, %StudyError{}} =
             FinalReplicaSummaryAssembler.assemble(context.final_phase, context.definition, 5)
  end

  defp item_at(%FinalReplicaSummary{items: items}, position) do
    Enum.find(items, &(&1.position == position)) ||
      flunk("expected a summary item at position #{position}")
  end

  defp first_run(item) do
    from(run in Run,
      where: run.experiment_id == ^item.experiment_id,
      order_by: run.trial_index,
      limit: 1
    )
    |> Repo.one!()
    |> Repo.preload(:iterations)
  end

  defp capability_id(graph, name) do
    graph
    |> Graph.nodes()
    |> Enum.filter(&(&1.type == MissionCapability and &1.data.name == name))
    |> case do
      [%{id: id}] -> id
      other -> flunk("expected one capability named #{name}, got #{inspect(other)}")
    end
  end

  defp canonical_view?(%Node{view_data: view_data}) do
    view_data.x_pos == 0.0 and view_data.y_pos == 0.0 and is_nil(view_data.radius)
  end

  defp canonical_view?(%Edge{}), do: false

  defp plan_actions(items, position) do
    item = Enum.at(items, position)
    run = Repo.get!(OptimizationRun, item.optimization_run_id)

    from(action in OptimizationAction,
      where: action.optimization_run_id == ^run.id,
      order_by: action.position
    )
    |> Repo.all()
    |> Enum.map(
      &%{
        position: &1.position,
        action_type: &1.action_type,
        target_id: &1.target_id,
        cost: &1.cost
      }
    )
  end

  defp stored_iteration_indexes(items, position) do
    item = Enum.at(items, position)

    runs =
      from(run in Run, where: run.experiment_id == ^item.experiment_id, order_by: run.trial_index)
      |> Repo.all()
      |> Repo.preload(:iterations)

    Enum.map(runs, fn run -> run.iterations |> Enum.map(& &1.index) |> Enum.sort() end)
  end

  defp stored_seeds(items, position) do
    item = Enum.at(items, position)

    from(run in Run, where: run.experiment_id == ^item.experiment_id, order_by: run.trial_index)
    |> Repo.all()
    |> Enum.map(& &1.seed)
  end
end
