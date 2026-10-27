defmodule NetworkDefense.Evaluation.Study.FinalTierWorkflowTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DagLoader
  alias Gust.Flows.Run

  alias NetworkDefense.Evaluation.Study.Actions.{
    CheckFinalEnvironment,
    CompleteFinalTier,
    PrepareFinalReplica
  }

  alias NetworkDefense.Evaluation.Study.{
    Collection,
    CollectionLimits,
    FinalTierAwaiter,
    FinalTierWorkflow,
    PhaseRuns
  }

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyFixtures, StudyPhase}

  @registry NetworkDefense.Evaluation.Study.CoordinatorRegistry

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(gust_owner) end)
    start_supervised!({DagLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})
    _definitions = DagLoader.get_definitions()
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    graph = StudyFixtures.insert_collection_graph("final-tier", mission: true)
    definition = StudyFixtures.collection_definition(graph.graph, graph.foothold)
    context = StudyFixtures.final_lifecycle(definition)
    {:ok, phase_run} = PhaseRuns.get_or_create(context.final_phase, "core", 0)
    previous = Application.get_env(:network_defense, :measured_environment_revision)

    Application.put_env(
      :network_defense,
      :measured_environment_revision,
      definition.study.revisions.environment
    )

    on_exit(fn ->
      if previous == nil,
        do: Application.delete_env(:network_defense, :measured_environment_revision),
        else: Application.put_env(:network_defense, :measured_environment_revision, previous)
    end)

    Map.put(context, :phase_run, phase_run)
  end

  test "CHUNK-B-ENV-01: WHEN the environment changes between boundaries, THE action SHALL read it again without disclosing values",
       context do
    args = [study_phase_run_id: context.phase_run.id]
    assert %{"study_phase_run_id" => _id} = CheckFinalEnvironment.execute(args, %{})

    Application.put_env(
      :network_defense,
      :measured_environment_revision,
      "private-observed-value"
    )

    error = assert_raise Gust.DAG.NonRecError, fn -> CheckFinalEnvironment.execute(args, %{}) end
    assert error.message =~ "measured_environment_changed"
    refute error.message =~ "private-observed-value"
    refute error.message =~ context.definition.study.revisions.environment
    Application.delete_env(:network_defense, :measured_environment_revision)

    assert_raise Gust.DAG.NonRecError, ~r/measured_environment_unavailable/, fn ->
      CheckFinalEnvironment.execute(args, %{})
    end
  end

  @tag type: :integration, case_id: "CHUNK-B-ENV-02"
  test "CHUNK-B-ENV-02: WHEN the phase-run UUID has no stored row, THE action SHALL raise the permanent storage error" do
    error =
      assert_raise Gust.DAG.NonRecError, fn ->
        CheckFinalEnvironment.execute([study_phase_run_id: Ecto.UUID.generate()], %{})
      end

    assert Jason.decode!(error.message) == %{
             "kind" => "network_defense.evaluation.study_error",
             "version" => 1,
             "error" => StudyError.to_params(StudyError.phase_run_storage_failed())
           }
  end

  test "CHUNK-B-PREP-01: WHEN warm-up or measured work is prepared, THE action SHALL preserve global tier positions",
       context do
    # The second tier must retain its complete-family positions.
    params = Definition.to_params(context.definition)
    [graph] = params["graphs"]
    [comparison] = params["family"]["comparisons"]

    params =
      params
      |> Map.put("graphs", [Map.put(graph, "tier", "edge"), graph])
      |> put_in(["final", "analysis", "comparison_seeds"], [210_001, 210_002])
      |> put_in(["family", "comparisons"], [Map.put(comparison, "tier", "edge"), comparison])
      |> put_in(["pilot", "collection", "roots"], [
        %{"tier" => "edge", "value" => 1},
        %{"tier" => "core", "value" => 2}
      ])
      |> put_in(["final", "collection", "roots"], [
        %{"tier" => "edge", "value" => 3},
        %{"tier" => "core", "value" => 4}
      ])

    assert {:ok, definition} = Definition.parse(params)
    study = StudyFixtures.final_lifecycle(definition)
    assert {:ok, phase_run} = PhaseRuns.get_or_create(study.final_phase, "core", 1)

    for position <- -1..4 do
      assert %{"gust_task_items" => mapped} =
               PrepareFinalReplica.execute(
                 [study_phase_run_id: phase_run.id, replica_position: position],
                 %{}
               )

      assert {:ok, work} =
               Collection.build_collection_work(
                 study.execution,
                 study.final_phase,
                 definition,
                 position
               )

      assert {:ok, expected} = Collection.filter_tier(work, definition, "core")
      items = Enum.map(mapped, &Repo.get!(StudyCollectionItem, &1["collection_item_id"]))
      assert Enum.map(items, & &1.item_position) == Enum.map(expected, & &1.item_position)
      assert hd(items).item_position > 0
      assert Enum.all?(items, &(&1.replica_position == position))
    end

    Repo.update!(Ecto.Changeset.change(phase_run, tier: "undeclared"))

    assert_raise Gust.DAG.NonRecError, ~r/invalid_tier/, fn ->
      PrepareFinalReplica.execute([study_phase_run_id: phase_run.id, replica_position: 0], %{})
    end

    assert_raise Gust.DAG.NonRecError, ~r/invalid_collection_position/, fn ->
      PrepareFinalReplica.execute([study_phase_run_id: phase_run.id, replica_position: 5], %{})
    end
  end

  @tag type: :backend_e2e, case_id: "CHUNK-B-FLOW-01", timeout: 90_000
  test "CHUNK-B-FLOW-01: WHEN the internal tier workflow runs, THE fixed DAG SHALL return five timings and only a tier receipt",
       context do
    assert {:ok, run_id} = FinalTierWorkflow.create(context.phase_run)
    assert %{status: :created, params: params} = Gust.Flows.get_run!(run_id)

    assert Enum.sort(Map.keys(params)) == [
             "execution_id",
             "study_phase_id",
             "study_phase_run_id",
             "tier",
             "tier_position"
           ]

    assert Repo.get!(StudyPhase, context.final_phase.id).gust_run_id == nil
    assert {:ok, linked} = PhaseRuns.link_gust_run(context.phase_run, run_id)
    assert {:ok, _owner} = Registry.register(@registry, context.execution.id, nil)
    on_exit(fn -> Registry.unregister(@registry, context.execution.id) end)
    assert :ok = FinalTierWorkflow.dispatch(run_id)
    assert {:ok, timings} = FinalTierWorkflow.await(context.execution, linked, 60_000)
    assert Enum.map(timings, & &1.position) == Enum.to_list(0..4)

    assert Enum.all?(
             timings,
             &(&1.tier == "core" and &1.total.elapsed_us >= &1.plan_selection.elapsed_us)
           )

    receipt = %{"study_phase_run_id" => linked.id, "tier" => "core", "tier_position" => 0}
    assert {:ok, ^receipt} = FinalTierWorkflow.result(run_id)
    assert ^receipt = CompleteFinalTier.execute([], %{run_id: run_id})
    assert Repo.get!(StudyPhase, context.final_phase.id).snapshot_id == nil
    assert Repo.get!(StudyPhase, context.final_phase.id).gust_run_id == nil

    [task] = Gust.Flows.get_tasks_by_name("complete_final_tier", run_id)

    task
    |> Gust.Flows.Task.changeset(%{result: %{receipt | "tier" => "wrong"}})
    |> Gust.Repo.update!()

    assert FinalTierWorkflow.result(run_id) ==
             {:error, StudyError.final_collection_workflow_failed()}

    # Matching task and run payloads cannot override the stored tier identity.
    run = Gust.Flows.get_run!(run_id)

    run
    |> Run.changeset(%{params: %{params | "tier" => "wrong"}})
    |> Gust.Repo.update!()

    assert FinalTierWorkflow.result(run_id) ==
             {:error, StudyError.final_collection_workflow_failed()}

    assert_raise Gust.DAG.NonRecError, ~r/final_timing_invalid/, fn ->
      CompleteFinalTier.execute([], %{run_id: run_id})
    end
  end

  test "CHUNK-B-FLOW-02: WHEN the tier identity is not stored, THE workflow SHALL reject creation",
       context do
    forged = %{context.phase_run | id: Ecto.UUID.generate()}
    assert {:error, %StudyError{}} = FinalTierWorkflow.create(forged)
    forged = %{context.phase_run | tier_position: 4}
    assert {:error, %StudyError{}} = FinalTierWorkflow.create(forged)

    assert FinalTierWorkflow.result(9_000_000) ==
             {:error, StudyError.final_collection_workflow_failed()}
  end

  @tag type: :integration, case_id: "CHUNK-B-FLOW-03", timeout: 90_000
  test "CHUNK-B-FLOW-03: WHEN an environment task fails, THE internal await boundary SHALL preserve its bounded error",
       context do
    Application.put_env(
      :network_defense,
      :measured_environment_revision,
      "private-changed-environment"
    )

    assert {:ok, run_id} = FinalTierWorkflow.create(context.phase_run)
    assert {:ok, linked} = PhaseRuns.link_gust_run(context.phase_run, run_id)
    assert :ok = FinalTierWorkflow.dispatch(run_id)

    assert FinalTierWorkflow.await(context.execution, linked, 60_000) ==
             {:error, StudyError.measured_environment_changed()}
  end

  @tag type: :backend_e2e, case_id: "CHUNK-B-FLOW-04", timeout: 90_000
  test "CHUNK-B-FLOW-04: WHEN the coordinator is absent, THE real workflow SHALL preserve the marker failure",
       context do
    assert Application.fetch_env!(:network_defense, :measured_environment_revision) ==
             context.definition.study.revisions.environment

    assert Registry.lookup(@registry, context.execution.id) == []
    assert {:ok, run_id} = FinalTierWorkflow.create(context.phase_run)
    assert {:ok, linked} = PhaseRuns.link_gust_run(context.phase_run, run_id)
    assert :ok = FinalTierWorkflow.dispatch(run_id)

    assert FinalTierWorkflow.await(context.execution, linked, 60_000) ==
             {:error, StudyError.final_timing_unavailable()}

    assert Registry.lookup(@registry, context.execution.id) == []
    assert %{status: :failed} = Gust.Flows.get_run!(run_id)

    assert [%{status: :succeeded}] =
             Gust.Flows.get_tasks_by_name("check_environment_before_0", run_id)

    assert [%{status: :failed, error: %{"message" => message}}] =
             Gust.Flows.get_tasks_by_name("mark_plan_dispatch_0", run_id)

    assert Jason.decode!(message) == %{
             "kind" => "network_defense.evaluation.study_error",
             "version" => 1,
             "error" => StudyError.to_params(StudyError.final_timing_unavailable())
           }
  end

  @tag type: :integration, case_id: "CHUNK-B-FLOW-05", timeout: 90_000
  test "CHUNK-B-FLOW-05: WHEN workflow error descriptions change, THE stable issue code SHALL preserve the stored task error",
       context do
    Application.put_env(
      :network_defense,
      :measured_environment_revision,
      "private-changed-environment"
    )

    assert {:ok, run_id} = FinalTierWorkflow.create(context.phase_run)
    assert {:ok, linked} = PhaseRuns.link_gust_run(context.phase_run, run_id)
    assert :ok = FinalTierWorkflow.dispatch(run_id)

    assert FinalTierWorkflow.await(context.execution, linked, 60_000) ==
             {:error, StudyError.measured_environment_changed()}

    assert [%{status: :failed, error: %{"message" => message}}] =
             Gust.Flows.get_tasks_by_name("check_environment_before_warm_up", run_id)

    assert Jason.decode!(message) == %{
             "kind" => "network_defense.evaluation.study_error",
             "version" => 1,
             "error" => StudyError.to_params(StudyError.measured_environment_changed())
           }

    generic = StudyError.final_collection_workflow_failed()
    [issue] = generic.issues

    changed_issue =
      Map.merge(issue, %{
        "message" => "The workflow stopped before collection finished.",
        "path" => ["final_collection", "workflow"],
        "details" => %{"boundary" => "tier"}
      })

    changed = %{generic | issues: [changed_issue]}
    refute changed == generic
    assert changed_issue["code"] == issue["code"]

    :meck.new(FinalTierAwaiter, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(FinalTierAwaiter) end)

    unrelated = %{
      changed
      | issues: [Map.put(changed_issue, "code", "unrelated_workflow_failure")]
    }

    :meck.expect(FinalTierAwaiter, :await, fn _execution, _phase_run, _timeout ->
      {:error, unrelated}
    end)

    assert FinalTierWorkflow.await(context.execution, linked, 60_000) == {:error, unrelated}

    :meck.expect(FinalTierAwaiter, :await, fn _execution, _phase_run, _timeout ->
      {:error, changed}
    end)

    assert FinalTierWorkflow.await(context.execution, linked, 60_000) ==
             {:error, StudyError.measured_environment_changed()}
  end

  @tag type: :integration, case_id: "CHUNK-B-FLOW-06"
  test "CHUNK-B-FLOW-06: WHEN collection limits are absent, THE workflow SHALL create a run for a declared stored tier",
       context do
    previous = Application.fetch_env(:network_defense, CollectionLimits)

    on_exit(fn ->
      case previous do
        {:ok, config} -> Application.put_env(:network_defense, CollectionLimits, config)
        :error -> Application.delete_env(:network_defense, CollectionLimits)
      end
    end)

    Application.delete_env(:network_defense, CollectionLimits)

    assert {:ok, run_id} = FinalTierWorkflow.create(context.phase_run)
    assert %{status: :created, params: params} = Gust.Flows.get_run!(run_id)
    assert params["study_phase_run_id"] == context.phase_run.id
    assert params["tier"] == context.phase_run.tier
    assert params["tier_position"] == context.phase_run.tier_position
  end

  @tag type: :integration, case_id: "CHUNK-B-FLOW-07"
  test "CHUNK-B-FLOW-07: WHEN the stored tier is unknown or empty, THE workflow SHALL reject creation",
       context do
    for tier <- ["undeclared", ""] do
      stored = Repo.update!(Ecto.Changeset.change(context.phase_run, tier: tier))
      assert FinalTierWorkflow.create(stored) == {:error, StudyError.invalid_tier()}
    end
  end

  test "CHUNK-B-DAG-01: WHEN the inactive DAG loads, THE graph SHALL contain six explicit sequential chains" do
    dag = Gust.Flows.get_dag_by_name("evaluation_study_final_tier_collection")
    assert {:ok, definition} = DagLoader.get_definition(dag.id)
    assert definition.error == %{}
    tasks = definition.tasks
    assert map_size(tasks) == 50

    warm_up = [
      "check_environment_before_warm_up",
      "prepare_warm_up",
      "run_plan_warm_up",
      "run_simulation_warm_up",
      "check_environment_before_0"
    ]

    measured =
      Enum.flat_map(0..4, fn position ->
        Enum.map(
          [
            "check_environment_before",
            "prepare",
            "mark_plan_dispatch",
            "run_plan",
            "mark_plan_completion",
            "mark_simulation_dispatch",
            "run_simulation",
            "mark_simulation_completion",
            "check_environment_after"
          ],
          &"#{&1}_#{position}"
        )
      end)

    chain = Enum.drop(warm_up, -1) ++ measured ++ ["complete_final_tier"]

    for [from, to] <- Enum.chunk_every(chain, 2, 1, :discard) do
      assert to in tasks[from][:downstream]
    end

    for suffix <- ["warm_up" | Enum.map(0..4, &to_string/1)] do
      assert to_string(tasks["run_plan_#{suffix}"][:map_over]) == "prepare_#{suffix}"
      assert to_string(tasks["run_simulation_#{suffix}"][:map_over]) == "prepare_#{suffix}"
    end
  end
end
