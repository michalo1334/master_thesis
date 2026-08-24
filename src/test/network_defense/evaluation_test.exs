defmodule NetworkDefense.EvaluationTest do
  use NetworkDefense.DataCase, async: true
  use Oban.Testing, repo: NetworkDefense.Repo

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.Contracts.EvaluationManifest, as: ManifestContract
  alias NetworkDefense.EvaluationFixtures

  alias NetworkDefense.Evaluation.{
    EvaluationManifest,
    EvaluationRun,
    EvaluationWorker,
    SeedSchedule
  }

  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Simulation.Seed

  import Ecto.Query
  import ExUnit.CaptureLog

  import NetworkDefense.EvaluationFixtures,
    only: [save_manifest: 1, save_manifest: 2, save_manifest: 3]

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, Run}

  @valid_manifest EvaluationFixtures.valid_manifest()

  defp manifest_id, do: "evaluation-#{System.unique_integer([:positive])}"

  describe "ManifestContract" do
    test "accepts a valid manifest" do
      assert {:ok, manifest} = ManifestContract.validate(@valid_manifest)
      assert manifest["id"] == "fixed-enterprise-v1"
    end

    test "accepts unknown fields and logs their paths" do
      manifest = Map.put(@valid_manifest, "bogus", 1)

      assert log =
               capture_log(fn ->
                 assert {:ok, ^manifest} = ManifestContract.validate(manifest)
               end)

      assert log =~ "$.bogus"
    end

    test "rejects an invalid schema version" do
      manifest = Map.put(@valid_manifest, "schema_version", 1)
      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "schema_version"))
    end

    test "rejects duplicate strategy and budget pairs" do
      manifest =
        Map.put(@valid_manifest, "strategy_runs", [
          %{"strategy" => "null", "budget" => 1, "selection_seeds" => [101]},
          %{"strategy" => "null", "budget" => 1, "selection_seeds" => [102]}
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs"))
    end

    test "rejects duplicate selection seeds" do
      manifest =
        Map.put(@valid_manifest, "strategy_runs", [
          %{"strategy" => "null", "budget" => 1, "selection_seeds" => [101, 101]}
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs.0.selection_seeds"))
    end

    test "rejects an unknown strategy" do
      manifest =
        Map.put(@valid_manifest, "strategy_runs", [
          %{"strategy" => "bogus", "budget" => 1, "selection_seeds" => [101]}
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs.0.strategy"))
    end

    test "rejects a manifest missing strategy runs without raising" do
      manifest = Map.delete(@valid_manifest, "strategy_runs")

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs"))
    end

    test "rejects a comparison with the same strategy and baseline" do
      manifest =
        put_in(@valid_manifest, ["analysis", "primary_comparisons"], [
          %{
            "strategy" => "null",
            "baseline" => "null",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.message == "strategy and baseline must differ"))
    end

    test "rejects an invalid graph revision UUID" do
      manifest =
        @valid_manifest
        |> Map.put("source", %{"type" => "graph_revision", "graph_revision_id" => "not-a-uuid"})
        |> Map.put("attacker", %{
          "entry_host" => %{"type" => "node_id", "value" => "not-a-uuid"},
          "max_attempts" => 1
        })

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "source.graph_revision_id"))
    end

    test "rejects empty strategy runs" do
      manifest = Map.put(@valid_manifest, "strategy_runs", [])
      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs"))
    end

    test "rejects invalid numeric values" do
      manifest = put_in(@valid_manifest, ["evaluation", "trials"], 0)
      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "evaluation.trials"))
    end

    test "parses a JSON string" do
      json = Jason.encode!(@valid_manifest)
      assert {:ok, manifest} = ManifestContract.parse(json)
      assert manifest["id"] == "fixed-enterprise-v1"
    end

    test "rejects invalid JSON" do
      assert {:error, errors} = ManifestContract.parse("{not json")
      assert Enum.any?(errors, &(&1.path == "$"))
    end
  end

  describe "SeedSchedule" do
    test "derives named streams from the evaluation seed" do
      schedule = SeedSchedule.build(@valid_manifest, "host-id")

      assert schedule.attack_evaluation_seed ==
               Seed.child_seed(9001, 3)

      assert schedule.topology_seed == 42
      assert schedule.entry_host_id == "host-id"
    end

    test "optimizer simulation seed derives from the selection seed" do
      assert SeedSchedule.optimizer_simulation_seed(101) == Seed.child_seed(101, 2)
    end

    test "changing the selection seed does not change the attack seed" do
      attack = SeedSchedule.attack_evaluation_seed(@valid_manifest)

      assert SeedSchedule.optimizer_simulation_seed(101) !=
               SeedSchedule.optimizer_simulation_seed(102)

      assert SeedSchedule.attack_evaluation_seed(@valid_manifest) == attack
    end
  end

  describe "Evaluation context" do
    test "saves, lists, and gets a manifest" do
      id = manifest_id()
      assert {:ok, manifest} = save_manifest(id)

      assert manifest.manifest_id == id

      assert Enum.any?(Evaluation.list(), &(&1.manifest_id == id))
      assert %EvaluationManifest{manifest_id: ^id} = Evaluation.get(manifest.id)
      assert %EvaluationManifest{manifest_id: ^id} = Evaluation.get_by_manifest_id(id)
    end

    test "upsert overwrites an existing manifest by manifest_id" do
      id = manifest_id()
      assert {:ok, _} = save_manifest(id)

      assert {:ok, updated} = save_manifest(id, @valid_manifest, "T2")

      assert updated.title == "T2"
      assert Enum.count(Evaluation.list(), &(&1.manifest_id == id)) == 1
    end

    test "save rejects an invalid manifest" do
      assert {:error, errors} =
               Evaluation.save(%{manifest_id: "m1", title: "T", content: %{"bad" => 1}})

      assert Enum.any?(errors, &(&1.path == "schema_version"))
    end

    test "start creates a run with a resolved graph revision" do
      id = manifest_id()
      assert {:ok, manifest} = save_manifest(id)

      assert {:ok, run} = Evaluation.start(id)
      assert %EvaluationRun{status: "running"} = run
      assert run.evaluation_manifest_id == manifest.id
      assert run.source_graph_revision_id != nil

      resolved = run.resolved_manifest
      assert get_in(resolved, ["source", "type"]) == "graph_revision"
      assert get_in(resolved, ["source", "graph_revision_id"]) == run.source_graph_revision_id
      assert get_in(resolved, ["attacker", "entry_host", "type"]) == "node_id"
      assert resolved["strategy_runs"] == @valid_manifest["strategy_runs"]
      assert resolved["analysis"] == @valid_manifest["analysis"]
    end

    test "start always creates a new run even for unchanged content" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id)

      assert {:ok, run} = Evaluation.start(id)
      revisions_after_first_start = graph_revision_count()

      assert {:ok, second} = Evaluation.start(id)
      assert second.id != run.id
      assert graph_revision_count() == revisions_after_first_start + 1
    end

    test "start creates a new run when strategies or budgets change" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id)
      assert {:ok, first} = Evaluation.start(id)

      strategies_changed =
        Map.put(@valid_manifest, "strategy_runs", [
          %{"strategy" => "null", "budget" => 1, "selection_seeds" => [101]},
          %{"strategy" => "random", "budget" => 1, "selection_seeds" => [102]}
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "random",
            "baseline" => "null",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert {:ok, _manifest} = save_manifest(id, strategies_changed)
      assert {:ok, second} = Evaluation.start(id)
      assert second.id != first.id
      assert second.resolved_manifest["strategy_runs"] == strategies_changed["strategy_runs"]

      budgets_changed =
        Map.put(@valid_manifest, "strategy_runs", [
          %{"strategy" => "null", "budget" => 1, "selection_seeds" => [101]},
          %{"strategy" => "cvss", "budget" => 2, "selection_seeds" => [102]},
          %{"strategy" => "random", "budget" => 2, "selection_seeds" => [103]}
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "random",
            "baseline" => "cvss",
            "budget" => 2,
            "outcome" => "blast_radius"
          }
        ])

      assert {:ok, _manifest} = save_manifest(id, budgets_changed)
      assert {:ok, third} = Evaluation.start(id)
      assert third.id != second.id
      assert third.resolved_manifest["strategy_runs"] == budgets_changed["strategy_runs"]
    end

    test "start creates a new run when topology inputs change" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id)
      assert {:ok, first} = Evaluation.start(id)

      changed_seed = put_in(@valid_manifest, ["source", "seed"], 43)
      assert {:ok, _manifest} = save_manifest(id, changed_seed)
      assert {:ok, second} = Evaluation.start(id)
      assert second.id != first.id
      assert second.source_graph_revision_id != first.source_graph_revision_id

      changed_hosts = put_in(@valid_manifest, ["source", "hosts"], 9)
      assert {:ok, _manifest} = save_manifest(id, changed_hosts)
      assert {:ok, third} = Evaluation.start(id)
      assert third.id != second.id
      assert third.source_graph_revision_id != second.source_graph_revision_id
    end

    test "start returns not_found for an unknown manifest id" do
      assert {:error, :not_found} = Evaluation.start("nope")
    end

    test "run completes a run whose source revision exists" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id)

      assert {:ok, run} = Evaluation.start(id)

      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.status == "completed"
    end

    test "run fails a run whose source revision is missing" do
      run = %NetworkDefense.Evaluation.EvaluationRun{
        id: Ecto.UUID.generate(),
        source_graph_revision_id: Ecto.UUID.generate(),
        status: "running"
      }

      assert {:ok, failed} = NetworkDefense.Evaluation.Evaluator.run(run)
      assert failed.status == "failed"
      assert failed.failure_reason != nil
    end
  end

  describe "Preflight" do
    test "resolves a graph revision source without generating a graph" do
      graph = NetworkDefense.Topology.EnterpriseTopology.generate(hosts: 8, seed: 1)
      assert {:ok, graph} = Graphs.insert(graph)

      host =
        Enum.find(
          NetworkDefense.Graph.Graph.nodes(graph),
          &(&1.type == NetworkDefense.Nodes.Host)
        )

      manifest = %{
        "source" => %{"type" => "graph_revision", "graph_revision_id" => graph.revision_id},
        "attacker" => %{
          "entry_host" => %{"type" => "node_id", "value" => host.id},
          "max_attempts" => 1
        },
        "model" => %{"require_pre_attack_feasibility" => false}
      }

      assert {:ok, resolved} = Evaluation.preflight(manifest)
      assert resolved.graph_revision_id == graph.revision_id
      assert resolved.entry_host_id == host.id
    end

    test "does not persist a topology when a later validation step fails" do
      revisions_before = graph_revision_count()

      manifest = %{
        "source" => %{
          "type" => "topology",
          "generator" => "enterprise",
          "hosts" => 8,
          "seed" => 42
        },
        "attacker" => %{
          "entry_host" => %{"type" => "semantic_key", "value" => "no-such-host"},
          "max_attempts" => 1
        },
        "model" => %{"require_pre_attack_feasibility" => true}
      }

      assert {:error, errors} = Evaluation.preflight(manifest)
      assert Enum.any?(errors, &(&1.path == "attacker.entry_host.value"))
      assert graph_revision_count() == revisions_before
    end

    test "rejects an infeasible graph revision without persisting a new revision" do
      graph = infeasible_graph()
      assert {:ok, graph} = Graphs.insert(graph)

      host =
        Enum.find(
          NetworkDefense.Graph.Graph.nodes(graph),
          &(&1.type == NetworkDefense.Nodes.Host)
        )

      revisions_before = graph_revision_count()

      manifest = %{
        "source" => %{"type" => "graph_revision", "graph_revision_id" => graph.revision_id},
        "attacker" => %{
          "entry_host" => %{"type" => "node_id", "value" => host.id},
          "max_attempts" => 1
        },
        "model" => %{"require_pre_attack_feasibility" => true}
      }

      assert {:error, errors} = Evaluation.preflight(manifest)
      assert Enum.any?(errors, &(&1.path == "model.require_pre_attack_feasibility"))
      assert graph_revision_count() == revisions_before
    end
  end

  describe "Evaluator integration" do
    @eval_manifest EvaluationFixtures.analysis_manifest()

    test "runs baseline and post-defense experiments with paired attack seeds" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id, @eval_manifest)

      assert {:ok, run} = Evaluation.start(id)
      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.status == "completed"

      experiments = experiments_for(run.id)
      assert [_, _, _] = experiments

      attack_seed = Seed.child_seed(9001, 3)
      assert Enum.all?(experiments, &(&1.master_seed == attack_seed))

      for experiment <- experiments do
        runs = runs_for(experiment.id)
        assert [_, _, _] = runs

        assert Enum.map(runs, & &1.seed) ==
                 Enum.map(1..3, &Seed.child_seed(attack_seed, &1))
      end

      [baseline | post_defense] = Enum.map(experiments, &runs_for(&1.id))

      assert Enum.all?(post_defense, fn runs ->
               Enum.map(baseline, & &1.seed) == Enum.map(runs, & &1.seed)
             end)
    end

    test "resuming a completed run does not duplicate plan or trial rows" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id, @eval_manifest)

      assert {:ok, run} = Evaluation.start(id)
      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.status == "completed"

      plan_count = optimization_run_count(run.id)
      experiment_count = length(experiments_for(run.id))
      trial_count = simulation_run_count(run.id)

      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.status == "completed"

      assert optimization_run_count(run.id) == plan_count
      assert length(experiments_for(run.id)) == experiment_count
      assert simulation_run_count(run.id) == trial_count
    end

    test "start always creates a new run even after completion" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id, @eval_manifest)

      assert {:ok, run} = Evaluation.start(id)
      assert {:ok, _} = Evaluation.run(run.id)

      assert {:ok, second} = Evaluation.start(id)
      assert second.id != run.id
      assert second.status == "running"
    end

    test "evaluation worker enqueues and executes a run" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id, @eval_manifest)

      assert {:ok, run} = Evaluation.start(id)
      run_id = run.id

      assert {:ok, _job} = OpentelemetryOban.insert(EvaluationWorker.new(%{"run_id" => run_id}))

      assert [
               %{
                 args: %{"run_id" => ^run_id},
                 queue: "evaluations",
                 max_attempts: 1,
                 meta: %{"traceparent" => _}
               }
             ] = all_enqueued(worker: EvaluationWorker)

      assert :ok = perform_job(EvaluationWorker, %{"run_id" => run_id})

      assert %{status: "completed"} = Repo.get!(EvaluationRun, run_id)
    end

    test "the database rejects a duplicate plan for the same selection seed" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id, @eval_manifest)

      assert {:ok, run} = Evaluation.start(id)

      attrs = %{
        graph_revision_id: run.source_graph_revision_id,
        evaluation_run_id: run.id,
        strategy: "null",
        requested_budget: 1,
        selection_seed: 101
      }

      assert {:ok, _} =
               NetworkDefense.Optimization.OptimizationRun.new(attrs)
               |> NetworkDefense.Optimization.OptimizationRuns.create()

      assert {:error, %Ecto.Changeset{}} =
               NetworkDefense.Optimization.OptimizationRun.new(attrs)
               |> NetworkDefense.Optimization.OptimizationRuns.create()
    end
  end

  describe "ManifestContract source/entry selector combination" do
    test "rejects a topology source with a node_id entry selector" do
      manifest =
        @valid_manifest
        |> Map.put("attacker", %{
          "entry_host" => %{"type" => "node_id", "value" => Ecto.UUID.generate()},
          "max_attempts" => 1
        })

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "attacker.entry_host.type"))
    end

    test "rejects a graph_revision source with a semantic_key entry selector" do
      manifest =
        @valid_manifest
        |> Map.put("source", %{
          "type" => "graph_revision",
          "graph_revision_id" => Ecto.UUID.generate()
        })
        |> Map.put("attacker", %{
          "entry_host" => %{"type" => "semantic_key", "value" => "internet"},
          "max_attempts" => 1
        })

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "attacker.entry_host.type"))
    end

    test "accepts unknown nested fields and logs their paths" do
      manifest = put_in(@valid_manifest, ["source", "bogus"], 1)

      assert log =
               capture_log(fn ->
                 assert {:ok, ^manifest} = ManifestContract.validate(manifest)
               end)

      assert log =~ "source.bogus"

      manifest = put_in(@valid_manifest, ["model", "bogus"], 1)

      assert log =
               capture_log(fn ->
                 assert {:ok, ^manifest} = ManifestContract.validate(manifest)
               end)

      assert log =~ "model.bogus"

      manifest = put_in(@valid_manifest, ["evaluation", "bogus"], 1)

      assert log =
               capture_log(fn ->
                 assert {:ok, ^manifest} = ManifestContract.validate(manifest)
               end)

      assert log =~ "evaluation.bogus"
    end
  end

  defp experiments_for(evaluation_run_id) do
    Experiment
    |> where([experiment], experiment.evaluation_run_id == ^evaluation_run_id)
    |> order_by([experiment], asc: experiment.inserted_at)
    |> Repo.all()
  end

  defp runs_for(experiment_id) do
    Run
    |> where([run], run.experiment_id == ^experiment_id)
    |> order_by([run], asc: run.trial_index)
    |> Repo.all()
  end

  defp optimization_run_count(evaluation_run_id) do
    from(run in NetworkDefense.Optimization.OptimizationRun,
      where: run.evaluation_run_id == ^evaluation_run_id,
      select: count(run.id)
    )
    |> Repo.one()
  end

  defp simulation_run_count(evaluation_run_id) do
    from(run in Run,
      join: experiment in Experiment,
      on: experiment.id == run.experiment_id,
      where: experiment.evaluation_run_id == ^evaluation_run_id,
      select: count(run.id)
    )
    |> Repo.one()
  end

  defp graph_revision_count do
    from(revision in NetworkDefense.Graph.GraphRevision, select: count(revision.id))
    |> Repo.one()
  end

  defp infeasible_graph do
    alias NetworkDefense.Graph.Graph
    alias NetworkDefense.GraphFixtures
    alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}
    alias NetworkDefense.Relationships.{Contains, Runs, SegmentReachability, Supports}

    graph = Graph.new(Ecto.UUID.generate())

    source_segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "Source"})
    target_segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "Target"})
    source_host = GraphFixtures.build_node(graph, Host, %{"name" => "source-host"})
    target_host = GraphFixtures.build_node(graph, Host, %{"name" => "target-host"})

    api =
      GraphFixtures.build_node(graph, Service, %{
        "name" => "api",
        "protocol" => "tcp",
        "port" => 8080
      })

    db_segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "DB"})
    db_host = GraphFixtures.build_node(graph, Host, %{"name" => "db-host"})

    db =
      GraphFixtures.build_node(graph, Service, %{
        "name" => "db",
        "protocol" => "tcp",
        "port" => 5432
      })

    capability =
      GraphFixtures.build_node(graph, MissionCapability, %{
        "name" => "orders",
        "impact_weight" => 8.0,
        "min_operational_support" => 1,
        "required_flows" => [
          %{"source_segment_id" => source_segment.id, "target_service_id" => api.id},
          %{"source_segment_id" => db_segment.id, "target_service_id" => db.id}
        ]
      })

    graph =
      Enum.reduce(
        [
          source_segment,
          target_segment,
          source_host,
          target_host,
          api,
          db_segment,
          db_host,
          db,
          capability
        ],
        graph,
        &Graph.add_node(&2, &1)
      )

    edges = [
      GraphFixtures.edge(Ecto.UUID.generate(), source_segment, source_host, Contains),
      GraphFixtures.edge(Ecto.UUID.generate(), target_segment, target_host, Contains),
      GraphFixtures.edge(Ecto.UUID.generate(), db_segment, db_host, Contains),
      GraphFixtures.edge(Ecto.UUID.generate(), target_host, api, Runs),
      GraphFixtures.edge(Ecto.UUID.generate(), db_host, db, Runs),
      GraphFixtures.edge(
        Ecto.UUID.generate(),
        source_segment,
        target_segment,
        SegmentReachability,
        %{"protocol" => "tcp"}
      ),
      GraphFixtures.edge(Ecto.UUID.generate(), source_host, capability, Supports),
      GraphFixtures.edge(Ecto.UUID.generate(), target_host, capability, Supports)
    ]

    Enum.reduce(edges, graph, &Graph.add_edge(&2, &1))
  end
end
