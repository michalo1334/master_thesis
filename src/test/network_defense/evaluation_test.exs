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
    only: [save_manifest: 1, save_manifest: 2]

  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, Run}

  @valid_manifest EvaluationFixtures.valid_manifest()

  defp manifest_id, do: "evaluation-#{System.unique_integer([:positive])}"

  describe "ManifestContract" do
    test "accepts a valid manifest" do
      assert {:ok, manifest} = ManifestContract.validate(@valid_manifest)
      assert manifest["id"] == "fixed-enterprise-v1"
    end

    test "accepts mission_only unchanged" do
      manifest =
        @valid_manifest
        |> put_in(["model_variants"], [
          %{
            "id" => "mission_only",
            "objective" => "mission_impact_only",
            "require_pre_attack_feasibility" => true
          }
        ])
        |> put_in(["strategy_runs", Access.all(), "model_variant"], "mission_only")
        |> put_in(
          ["analysis", "primary_comparisons", Access.all(), "model_variant"],
          "mission_only"
        )
        |> put_in(
          ["analysis", "primary_comparisons", Access.all(), "baseline_model_variant"],
          "mission_only"
        )

      assert {:ok, ^manifest} = ManifestContract.validate(manifest)
    end

    test "accepts all six canonical model variants" do
      manifest =
        @valid_manifest
        |> put_in(["model_variants"], EvaluationFixtures.canonical_variants())
        |> Map.put("strategy_runs", canonical_plan_runs())
        |> put_in(["analysis", "primary_comparisons"], [
          comparison("full", "blast_only"),
          comparison("blast_only", "blast_only_unconstrained"),
          comparison("mission_only", "mission_only_unconstrained")
        ])

      assert {:ok, ^manifest} = ManifestContract.validate(manifest)
    end

    test "rejects feasibility that differs from the canonical definition" do
      manifest =
        put_in(
          @valid_manifest,
          ["model_variants"],
          [
            %{
              "id" => "blast_only",
              "objective" => "blast_radius_only",
              "require_pre_attack_feasibility" => false
            }
          ]
        )

      assert {:error, errors} = ManifestContract.validate(manifest)

      assert Enum.any?(
               errors,
               &(&1.path == "model_variants.0.require_pre_attack_feasibility")
             )
    end

    test "accepts objective-only and feasibility-only cross-model comparisons" do
      manifest =
        @valid_manifest
        |> put_in(["model_variants"], [
          variant("full"),
          variant("blast_only"),
          variant("blast_only_unconstrained")
        ])
        |> Map.put("strategy_runs", [
          plan("full"),
          plan("blast_only"),
          plan("blast_only_unconstrained")
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          comparison("full", "blast_only"),
          comparison("blast_only", "blast_only_unconstrained")
        ])

      assert {:ok, ^manifest} = ManifestContract.validate(manifest)
    end

    test "rejects a confounded cross-model comparison" do
      manifest =
        @valid_manifest
        |> put_in(["model_variants"], [
          variant("full"),
          variant("blast_only_unconstrained")
        ])
        |> Map.put("strategy_runs", [
          plan("full"),
          plan("blast_only_unconstrained")
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          comparison("full", "blast_only_unconstrained")
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)

      assert Enum.any?(
               errors,
               &(&1.message ==
                   "cross-model comparisons must vary only one of objective or feasibility")
             )
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

    test "requires a model version" do
      assert {:error, errors} =
               @valid_manifest |> Map.delete("model_version") |> ManifestContract.validate()

      assert Enum.any?(errors, &(&1.path == "model_version"))
    end

    test "rejects duplicate model variant, strategy, and budget plans" do
      manifest =
        Map.put(@valid_manifest, "strategy_runs", [
          %{
            "model_variant" => "full",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [101]
          },
          %{
            "model_variant" => "full",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [102]
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs"))
    end

    test "accepts the same strategy and budget on different model variants" do
      manifest =
        @valid_manifest
        |> put_in(["model_variants"], [
          %{
            "id" => "full",
            "objective" => "mission_then_blast_radius",
            "require_pre_attack_feasibility" => true
          },
          %{
            "id" => "blast_only_unconstrained",
            "objective" => "blast_radius_only",
            "require_pre_attack_feasibility" => false
          }
        ])
        |> Map.put("strategy_runs", [
          %{
            "model_variant" => "full",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [101]
          },
          %{
            "model_variant" => "blast_only_unconstrained",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [101]
          },
          %{
            "model_variant" => "full",
            "strategy" => "simulation_informed",
            "budget" => 1,
            "selection_seeds" => [201]
          }
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "simulation_informed",
            "model_variant" => "full",
            "baseline" => "null",
            "baseline_model_variant" => "full",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert {:ok, ^manifest} = ManifestContract.validate(manifest)
    end

    test "rejects duplicate selection seeds" do
      manifest =
        Map.put(@valid_manifest, "strategy_runs", [
          %{
            "model_variant" => "full",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [101, 101]
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs.0.selection_seeds"))
    end

    test "rejects an unknown strategy" do
      manifest =
        Map.put(@valid_manifest, "strategy_runs", [
          %{
            "model_variant" => "full",
            "strategy" => "bogus",
            "budget" => 1,
            "selection_seeds" => [101]
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs.0.strategy"))
    end

    test "rejects a strategy run referencing an unknown model variant" do
      manifest =
        Map.put(@valid_manifest, "strategy_runs", [
          %{
            "model_variant" => "missing",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [101]
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs.0.model_variant"))
    end

    test "rejects duplicate model variant ids" do
      manifest =
        Map.put(@valid_manifest, "model_variants", [
          %{
            "id" => "full",
            "objective" => "mission_then_blast_radius",
            "require_pre_attack_feasibility" => true
          },
          %{
            "id" => "full",
            "objective" => "mission_then_blast_radius",
            "require_pre_attack_feasibility" => true
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "model_variants"))
    end

    test "rejects empty model variants" do
      manifest = Map.put(@valid_manifest, "model_variants", [])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "model_variants"))
    end

    test "rejects an unknown objective" do
      variants = get_in(@valid_manifest, ["model_variants"])
      variant = variants |> hd() |> Map.put("objective", "bogus")
      manifest = Map.put(@valid_manifest, "model_variants", [variant])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "model_variants.0.objective"))
    end

    test "rejects model-variant settings that differ from the canonical definition" do
      manifest =
        put_in(
          @valid_manifest,
          ["model_variants", Access.at(0), "objective"],
          "blast_radius_only"
        )

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "model_variants.0.objective"))
    end

    test "rejects a manifest missing strategy runs without raising" do
      manifest = Map.delete(@valid_manifest, "strategy_runs")

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "strategy_runs"))
    end

    test "rejects a comparison with identical sides" do
      manifest =
        put_in(@valid_manifest, ["analysis", "primary_comparisons"], [
          %{
            "strategy" => "null",
            "model_variant" => "full",
            "baseline" => "null",
            "baseline_model_variant" => "full",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.message == "comparison sides must differ"))
    end

    test "accepts a same-strategy cross-model comparison with matching selection seeds" do
      manifest = two_variant_manifest()

      assert {:ok, ^manifest} = ManifestContract.validate(manifest)
    end

    test "rejects a comparison referencing an undeclared model variant plan" do
      manifest =
        put_in(@valid_manifest, ["analysis", "primary_comparisons"], [
          %{
            "strategy" => "cvss",
            "model_variant" => "missing",
            "baseline" => "null",
            "baseline_model_variant" => "full",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "analysis.primary_comparisons.0.strategy"))
    end

    test "rejects a same-strategy cross-model comparison with mismatched selection seeds" do
      runs = two_variant_manifest()["strategy_runs"]

      mismatched =
        List.replace_at(runs, 1, %{
          "model_variant" => "blast_only",
          "strategy" => "simulation_informed",
          "budget" => 1,
          "selection_seeds" => [310]
        })

      manifest =
        two_variant_manifest()
        |> Map.put("strategy_runs", mismatched)
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "simulation_informed",
            "model_variant" => "full",
            "baseline" => "simulation_informed",
            "baseline_model_variant" => "blast_only",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)

      assert Enum.any?(
               errors,
               &(&1.message ==
                   "same-strategy comparisons must declare identical ordered selection seeds")
             )
    end

    test "rejects a cross-model comparison using model-unaware strategies" do
      manifest =
        two_variant_manifest()
        |> put_in(["strategy_runs"], [
          %{
            "model_variant" => "full",
            "strategy" => "cvss",
            "budget" => 1,
            "selection_seeds" => [101]
          },
          %{
            "model_variant" => "blast_only",
            "strategy" => "cvss",
            "budget" => 1,
            "selection_seeds" => [101]
          }
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "cvss",
            "model_variant" => "full",
            "baseline" => "cvss",
            "baseline_model_variant" => "blast_only",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert {:error, errors} = ManifestContract.validate(manifest)
      assert Enum.any?(errors, &(&1.path == "analysis.primary_comparisons.0"))
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

    test "updates only the explicitly selected manifest" do
      id = manifest_id()
      assert {:ok, original} = save_manifest(id)

      assert {:ok, updated} =
               Evaluation.save(%{
                 manifest_id: "different-id",
                 existing_manifest_id: original.id,
                 title: "T2",
                 content: Map.put(@valid_manifest, "id", "different-id")
               })

      assert updated.title == "T2"
      assert updated.manifest_id == "different-id"
      assert Evaluation.get(original.id).manifest_id == "different-id"
    end

    test "creating a duplicate manifest_id returns a unique constraint error" do
      id = manifest_id()
      assert {:ok, original} = save_manifest(id)

      assert {:error, changeset} =
               Evaluation.save(%{
                 manifest_id: id,
                 title: "T2",
                 content: Map.put(@valid_manifest, "id", id)
               })

      assert "has already been taken" in errors_on(changeset).manifest_id
      assert Evaluation.get(original.id).title == "T"
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
          %{
            "model_variant" => "full",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [101]
          },
          %{
            "model_variant" => "full",
            "strategy" => "random",
            "budget" => 1,
            "selection_seeds" => [102]
          }
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "random",
            "model_variant" => "full",
            "baseline" => "null",
            "baseline_model_variant" => "full",
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
          %{
            "model_variant" => "full",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [101]
          },
          %{
            "model_variant" => "full",
            "strategy" => "cvss",
            "budget" => 2,
            "selection_seeds" => [102]
          },
          %{
            "model_variant" => "full",
            "strategy" => "random",
            "budget" => 2,
            "selection_seeds" => [103]
          }
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "random",
            "model_variant" => "full",
            "baseline" => "cvss",
            "baseline_model_variant" => "full",
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
      assert is_integer(completed.runtime_ms)
      assert completed.runtime_ms >= 0
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
        "model_variants" => [
          %{
            "id" => "full",
            "objective" => "mission_then_blast_radius",
            "require_pre_attack_feasibility" => false
          }
        ]
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
        "model_variants" => [
          %{
            "id" => "full",
            "objective" => "mission_then_blast_radius",
            "require_pre_attack_feasibility" => true
          }
        ]
      }

      assert {:error, errors} = Evaluation.preflight(manifest)
      assert Enum.any?(errors, &(&1.path == "attacker.entry_host.value"))
      assert graph_revision_count() == revisions_before
    end

    test "rejects an infeasible graph revision when any variant requires feasibility" do
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
        "model_variants" => [
          %{
            "id" => "blast_only_unconstrained",
            "objective" => "blast_radius_only",
            "require_pre_attack_feasibility" => false
          },
          %{
            "id" => "full",
            "objective" => "mission_then_blast_radius",
            "require_pre_attack_feasibility" => true
          }
        ]
      }

      assert {:error, errors} = Evaluation.preflight(manifest)
      assert Enum.any?(errors, &(&1.path == "model_variants.1.require_pre_attack_feasibility"))
      assert graph_revision_count() == revisions_before
    end

    test "allows an infeasible graph revision when all variants disable feasibility" do
      graph = infeasible_graph()
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
        "model_variants" => [
          %{
            "id" => "blast_only_unconstrained",
            "objective" => "blast_radius_only",
            "require_pre_attack_feasibility" => false
          }
        ]
      }

      assert {:ok, resolved} = Evaluation.preflight(manifest)
      assert resolved.graph_revision_id == graph.revision_id
    end
  end

  describe "Import" do
    test "imports a valid JSON manifest and reuses identical content" do
      id = manifest_id()
      json = Jason.encode!(Map.put(@valid_manifest, "id", id))

      assert {:ok, result} = Evaluation.import_manifest(json)
      assert result.manifest_id == id
      assert result.status == "imported"
      assert result.title == id

      assert {:ok, %{status: "reused", title: ^id}} = Evaluation.import_manifest(json)
    end

    test "honors an explicit title" do
      id = manifest_id()
      json = Jason.encode!(Map.put(@valid_manifest, "id", id))

      assert {:ok, %{title: "My Title"}} = Evaluation.import_manifest(json, "My Title")
    end

    test "rejects a conflicting import with different content" do
      id = manifest_id()
      json = Jason.encode!(Map.put(@valid_manifest, "id", id))
      assert {:ok, _result} = Evaluation.import_manifest(json)

      changed =
        @valid_manifest
        |> Map.put("id", id)
        |> put_in(["evaluation", "trials"], 99)

      assert {:error, :conflict} = Evaluation.import_manifest(Jason.encode!(changed))
    end

    test "rejects invalid JSON" do
      assert {:error, errors} = Evaluation.import_manifest("{not json")
      assert Enum.any?(errors, &(&1.path == "$"))
    end
  end

  describe "Freeze" do
    test "resolves and persists a topology source into a graph-revision manifest" do
      source_id = manifest_id()
      assert {:ok, _manifest} = save_manifest(source_id)
      target_id = "frozen-#{source_id}"

      assert {:ok, result} = Evaluation.freeze(source_id, target_id, "Frozen copy")
      assert result.source_manifest_id == source_id
      assert result.target_manifest_id == target_id
      assert result.graph_revision_id != nil
      assert result.entry_host_id != nil

      target = Evaluation.get_by_manifest_id(target_id)
      assert target.title == "Frozen copy"
      assert get_in(target.content, ["source", "type"]) == "graph_revision"
      assert get_in(target.content, ["source", "graph_revision_id"]) == result.graph_revision_id
      assert get_in(target.content, ["attacker", "entry_host", "type"]) == "node_id"
      assert get_in(target.content, ["attacker", "entry_host", "value"]) == result.entry_host_id
    end

    test "rejects a source that is not a topology-source manifest" do
      source_id = manifest_id()
      assert {:ok, _manifest} = save_manifest(source_id)
      first_target = "frozen-#{source_id}"
      assert {:ok, _} = Evaluation.freeze(source_id, first_target)

      assert {:error, :source_not_topology} =
               Evaluation.freeze(first_target, "frozen-#{source_id}-again")
    end

    test "refuses an existing frozen target before creating a graph revision" do
      source_id = manifest_id()
      assert {:ok, _manifest} = save_manifest(source_id)
      target_id = "frozen-#{source_id}"
      assert {:ok, _} = Evaluation.freeze(source_id, target_id)

      revisions_before = graph_revision_count()
      assert {:error, :target_exists} = Evaluation.freeze(source_id, target_id)
      assert graph_revision_count() == revisions_before
    end

    test "rejects an invalid target before creating a graph revision" do
      source_id = manifest_id()
      assert {:ok, _manifest} = save_manifest(source_id)
      revisions_before = graph_revision_count()

      assert {:error, :invalid_target_manifest_id} = Evaluation.freeze(source_id, "")
      assert graph_revision_count() == revisions_before
    end

    test "returns not_found for an unknown source manifest" do
      assert {:error, :not_found} = Evaluation.freeze("no-such-source", "frozen-x")
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

      runtime_ms = completed.runtime_ms

      plan_count = optimization_run_count(run.id)
      experiment_count = length(experiments_for(run.id))
      trial_count = simulation_run_count(run.id)

      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.status == "completed"
      assert completed.runtime_ms == runtime_ms

      assert optimization_run_count(run.id) == plan_count
      assert length(experiments_for(run.id)) == experiment_count
      assert simulation_run_count(run.id) == trial_count
    end

    test "persists distinct plans per model variant on shared attack seeds and resumes idempotently" do
      id = manifest_id()

      eval_manifest =
        @valid_manifest
        |> put_in(["model_variants"], [
          %{
            "id" => "full",
            "objective" => "mission_then_blast_radius",
            "require_pre_attack_feasibility" => true
          },
          %{
            "id" => "blast_only",
            "objective" => "blast_radius_only",
            "require_pre_attack_feasibility" => true
          }
        ])
        |> Map.put("strategy_runs", [
          %{
            "model_variant" => "full",
            "strategy" => "simulation_informed",
            "budget" => 1,
            "selection_seeds" => [310]
          },
          %{
            "model_variant" => "blast_only",
            "strategy" => "simulation_informed",
            "budget" => 1,
            "selection_seeds" => [310]
          }
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "simulation_informed",
            "model_variant" => "full",
            "baseline" => "simulation_informed",
            "baseline_model_variant" => "blast_only",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])
        |> put_in(["evaluation", "trials"], 3)

      assert {:ok, _manifest} = save_manifest(id, eval_manifest)

      assert {:ok, run} = Evaluation.start(id)
      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.status == "completed"

      plans = plans_for(run.id)

      assert MapSet.new(Enum.map(plans, &{&1.model_variant, &1.strategy, &1.selection_seed})) ==
               MapSet.new([
                 {:full, "simulation_informed", 310},
                 {:blast_only, "simulation_informed", 310}
               ])

      assert [_, _] = plans |> Enum.map(& &1.id) |> Enum.uniq()

      experiments = experiments_for(run.id)
      assert [_, _, _] = experiments

      attack_seed = Seed.child_seed(9001, 3)
      assert Enum.all?(experiments, &(&1.master_seed == attack_seed))

      ordered_seeds = Enum.map(runs_for(hd(experiments).id), & &1.seed)

      for experiment <- experiments do
        assert Enum.map(runs_for(experiment.id), & &1.seed) == ordered_seeds
      end

      Repo.update!(Ecto.Changeset.change(%EvaluationRun{id: run.id}, status: "running"))

      assert {:ok, resumed} =
               NetworkDefense.Evaluation.Evaluator.run(Repo.get!(EvaluationRun, run.id))

      assert resumed.status == "completed"
      assert [_, _] = plans_for(run.id)
      assert [_, _, _] = experiments_for(run.id)
    end

    test "runs three distinct plans across variants on a shared attack schedule" do
      id = manifest_id()

      manifest =
        @valid_manifest
        |> put_in(["model_variants"], [
          variant("full"),
          variant("blast_only"),
          variant("mission_only")
        ])
        |> Map.put("strategy_runs", [
          plan("full"),
          plan("blast_only"),
          plan("mission_only")
        ])
        |> put_in(["analysis", "primary_comparisons"], [
          comparison("full", "blast_only"),
          comparison("blast_only", "mission_only")
        ])
        |> put_in(["evaluation", "trials"], 3)

      assert {:ok, _manifest} = save_manifest(id, manifest)

      assert {:ok, run} = Evaluation.start(id)
      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.status == "completed"

      plans = plans_for(run.id)

      assert MapSet.new(Enum.map(plans, &{&1.model_variant, &1.strategy, &1.selection_seed})) ==
               MapSet.new([
                 {:full, "simulation_informed", 310},
                 {:blast_only, "simulation_informed", 310},
                 {:mission_only, "simulation_informed", 310}
               ])

      assert [_, _, _] = plans |> Enum.map(& &1.id) |> Enum.uniq()

      experiments = experiments_for(run.id)
      assert [_, _, _, _] = experiments

      attack_seed = Seed.child_seed(9001, 3)
      assert Enum.all?(experiments, &(&1.master_seed == attack_seed))

      ordered_seeds = Enum.map(runs_for(hd(experiments).id), & &1.seed)

      for experiment <- experiments do
        assert Enum.map(runs_for(experiment.id), & &1.seed) == ordered_seeds
      end
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
        model_variant: :full,
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

    test "persists a plan for a new canonical model variant" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id)

      assert {:ok, run} = Evaluation.start(id)

      attrs = %{
        graph_revision_id: run.source_graph_revision_id,
        evaluation_run_id: run.id,
        model_variant: :blast_only,
        strategy: "null",
        requested_budget: 1,
        selection_seed: 201
      }

      assert {:ok, persisted} =
               NetworkDefense.Optimization.OptimizationRun.new(attrs)
               |> NetworkDefense.Optimization.OptimizationRuns.create()

      assert persisted.model_variant == :blast_only

      loaded = Repo.get!(NetworkDefense.Optimization.OptimizationRun, persisted.id)
      assert loaded.model_variant == :blast_only
    end
  end

  describe "Warm-up" do
    @warmup_manifest EvaluationFixtures.analysis_manifest() |> put_in(["evaluation", "trials"], 1)

    test "restricts purpose to evaluation and warmup in the changeset" do
      base = %{
        evaluation_manifest_id: Ecto.UUID.generate(),
        source_graph_revision_id: Ecto.UUID.generate(),
        resolved_manifest: %{},
        status: "running"
      }

      assert EvaluationRun.changeset(%EvaluationRun{}, base).valid?

      assert Ecto.Changeset.get_field(EvaluationRun.changeset(%EvaluationRun{}, base), :purpose) ==
               "evaluation"

      assert EvaluationRun.changeset(%EvaluationRun{}, Map.put(base, :purpose, "warmup")).valid?

      changeset =
        EvaluationRun.changeset(%EvaluationRun{}, Map.put(base, :purpose, "other"))

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:purpose]
    end

    test "runs synchronously as a completed warmup run" do
      id = manifest_id()
      assert {:ok, _manifest} = save_manifest(id, @warmup_manifest)

      assert {:ok, run} = Evaluation.warm_up(id)
      assert run.status == "completed"
      assert run.purpose == "warmup"
    end

    test "a completed warmup cannot be exported or analyzed but a normal run can" do
      warm_id = manifest_id()
      assert {:ok, _manifest} = save_manifest(warm_id, @warmup_manifest)
      assert {:ok, warmup} = Evaluation.warm_up(warm_id)

      assert {:error, :not_exportable} = Evaluation.download_archive(warmup.id)
      assert {:error, :not_exportable} = Evaluation.analyze(warmup.id, "analyze")

      eval_id = manifest_id()
      assert {:ok, _manifest} = save_manifest(eval_id, @warmup_manifest)
      assert {:ok, run} = Evaluation.start(eval_id)
      assert {:ok, completed} = Evaluation.run(run.id)
      assert completed.purpose == "evaluation"
      assert {:ok, _zip, _filename} = Evaluation.download_archive(completed.id)
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

      [variant] = get_in(@valid_manifest, ["model_variants"])
      manifest = put_in(@valid_manifest, ["model_variants"], [Map.put(variant, "bogus", 1)])

      assert log =
               capture_log(fn ->
                 assert {:ok, ^manifest} = ManifestContract.validate(manifest)
               end)

      assert log =~ "model_variants.0.bogus"

      manifest = put_in(@valid_manifest, ["evaluation", "bogus"], 1)

      assert log =
               capture_log(fn ->
                 assert {:ok, ^manifest} = ManifestContract.validate(manifest)
               end)

      assert log =~ "evaluation.bogus"
    end
  end

  defp variant(id),
    do: Enum.find(EvaluationFixtures.canonical_variants(), &(&1["id"] == id))

  defp plan(variant) do
    %{
      "model_variant" => variant,
      "strategy" => "simulation_informed",
      "budget" => 1,
      "selection_seeds" => [310]
    }
  end

  defp comparison(variant, baseline_variant) do
    %{
      "strategy" => "simulation_informed",
      "model_variant" => variant,
      "baseline" => "simulation_informed",
      "baseline_model_variant" => baseline_variant,
      "budget" => 1,
      "outcome" => "blast_radius"
    }
  end

  defp canonical_plan_runs do
    Enum.map(EvaluationFixtures.canonical_variants(), &plan(&1["id"]))
  end

  defp two_variant_manifest do
    @valid_manifest
    |> put_in(["model_variants"], [
      %{
        "id" => "full",
        "objective" => "mission_then_blast_radius",
        "require_pre_attack_feasibility" => true
      },
      %{
        "id" => "blast_only",
        "objective" => "blast_radius_only",
        "require_pre_attack_feasibility" => true
      }
    ])
    |> Map.put("strategy_runs", [
      %{
        "model_variant" => "full",
        "strategy" => "simulation_informed",
        "budget" => 1,
        "selection_seeds" => [310, 311]
      },
      %{
        "model_variant" => "blast_only",
        "strategy" => "simulation_informed",
        "budget" => 1,
        "selection_seeds" => [310, 311]
      }
    ])
    |> put_in(["analysis", "primary_comparisons"], [
      %{
        "strategy" => "simulation_informed",
        "model_variant" => "full",
        "baseline" => "simulation_informed",
        "baseline_model_variant" => "blast_only",
        "budget" => 1,
        "outcome" => "blast_radius"
      }
    ])
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

  defp plans_for(evaluation_run_id) do
    NetworkDefense.Optimization.OptimizationRun
    |> where([run], run.evaluation_run_id == ^evaluation_run_id)
    |> Repo.all()
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
