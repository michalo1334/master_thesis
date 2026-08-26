defmodule Mix.Tasks.Seed.FixedOrderFulfilmentTest do
  use NetworkDefense.DataCase, async: false

  import ExUnit.CaptureIO

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.Contracts.EvaluationManifest, as: ManifestContract
  alias NetworkDefense.Evaluation.OutputContract
  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Topology.FixedOrderFulfilmentScenario

  test "seeds the fixed scenario graph and both manifests idempotently" do
    first = run_task()
    second = run_task()

    assert %{
             "graph_revision_id" => revision_id,
             "manifest_id" => manifest_id,
             "entry_host_id" => entry_host_id,
             "revision_reused" => false,
             "manifest_reused" => false,
             "feasibility_manifest_id" => feasibility_manifest_id,
             "feasibility_entry_host_id" => feasibility_entry_host_id,
             "feasibility_manifest_reused" => false
           } = first

    assert %{
             "graph_revision_id" => ^revision_id,
             "manifest_id" => ^manifest_id,
             "entry_host_id" => ^entry_host_id,
             "revision_reused" => true,
             "manifest_reused" => true,
             "feasibility_manifest_id" => ^feasibility_manifest_id,
             "feasibility_entry_host_id" => ^feasibility_entry_host_id,
             "feasibility_manifest_reused" => true
           } = second

    assert manifest_id == FixedOrderFulfilmentScenario.manifest_id()
    assert feasibility_manifest_id == FixedOrderFulfilmentScenario.feasibility_manifest_id()

    severity_manifest = Evaluation.get_by_manifest_id(manifest_id)
    feasibility_manifest = Evaluation.get_by_manifest_id(feasibility_manifest_id)

    assert severity_manifest.title == FixedOrderFulfilmentScenario.title()
    assert feasibility_manifest.title == FixedOrderFulfilmentScenario.feasibility_manifest_title()

    assert Enum.map(severity_manifest.content["model_variants"], & &1["id"]) == ["full"]

    assert Enum.map(feasibility_manifest.content["model_variants"], & &1["id"]) == [
             "blast_only",
             "blast_only_unconstrained"
           ]

    initial_summaries =
      Graphs.list_summaries()
      |> Enum.filter(
        &(&1.title == FixedOrderFulfilmentScenario.title() and
            &1.revisionKind == "initial")
      )

    assert [summary] = initial_summaries
    assert summary.revisionId == revision_id

    for {manifest_id, expected_entry} <- [
          {manifest_id, entry_host_id},
          {feasibility_manifest_id, feasibility_entry_host_id}
        ] do
      manifest = Evaluation.get_by_manifest_id(manifest_id)
      assert manifest
      assert {:ok, _content} = ManifestContract.validate(manifest.content)

      assert manifest.content["source"] == %{
               "type" => "graph_revision",
               "graph_revision_id" => revision_id
             }

      assert manifest.content["attacker"]["entry_host"] == %{
               "type" => "node_id",
               "value" => expected_entry
             }
    end

    graph = Graphs.load_revision(revision_id)

    entry_host =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "internet-entry"))

    assert entry_host.id == entry_host_id

    feasibility_entry =
      Enum.find(Graph.nodes(graph), &(&1.type == Host and &1.data.name == "order-gateway"))

    assert feasibility_entry.id == feasibility_entry_host_id
  end

  test "rebinds a stale manifest to the persisted scenario revision" do
    seeded = run_task()
    manifest = Evaluation.get_by_manifest_id(seeded["manifest_id"])

    {:ok, _manifest} =
      Evaluation.save(%{
        existing_manifest_id: manifest.id,
        manifest_id: manifest.manifest_id,
        title: manifest.title,
        content:
          FixedOrderFulfilmentScenario.manifest_content(
            Ecto.UUID.generate(),
            Ecto.UUID.generate()
          )
      })

    rebound = run_task()

    assert rebound["manifest_reused"] == false

    manifest = Evaluation.get_by_manifest_id(seeded["manifest_id"])

    assert get_in(manifest.content, ["source", "graph_revision_id"]) ==
             seeded["graph_revision_id"]

    assert get_in(manifest.content, ["attacker", "entry_host", "value"]) ==
             seeded["entry_host_id"]
  end

  test "rebinds a manifest whose evaluation content differs from the builder" do
    seeded = run_task()
    manifest = Evaluation.get_by_manifest_id(seeded["manifest_id"])

    altered =
      put_in(manifest.content, ["evaluation", "trials"], 99)

    {:ok, _manifest} = Evaluation.save(%{existing_manifest_id: manifest.id, content: altered})

    rebound = run_task()
    assert rebound["manifest_reused"] == false

    manifest = Evaluation.get_by_manifest_id(seeded["manifest_id"])

    assert manifest.content ==
             FixedOrderFulfilmentScenario.manifest_content(
               seeded["graph_revision_id"],
               seeded["entry_host_id"]
             )
  end

  test "rebinds a stale feasibility manifest to the persisted scenario revision" do
    seeded = run_task()
    feasibility_id = seeded["feasibility_manifest_id"]
    manifest = Evaluation.get_by_manifest_id(feasibility_id)

    altered =
      put_in(manifest.content, ["evaluation", "trials"], 99)

    {:ok, _manifest} = Evaluation.save(%{existing_manifest_id: manifest.id, content: altered})

    rebound = run_task()
    assert rebound["feasibility_manifest_reused"] == false

    manifest = Evaluation.get_by_manifest_id(feasibility_id)

    assert manifest.content ==
             FixedOrderFulfilmentScenario.feasibility_manifest_content(
               seeded["graph_revision_id"],
               seeded["feasibility_entry_host_id"]
             )
  end

  test "produces a null-vs-cvss one-trial evaluation archive" do
    seeded = run_task()
    manifest_id = seeded["manifest_id"]
    manifest = Evaluation.get_by_manifest_id(manifest_id)

    probe =
      FixedOrderFulfilmentScenario.manifest_content(
        seeded["graph_revision_id"],
        seeded["entry_host_id"]
      )
      |> Map.put("strategy_runs", [
        %{
          "model_variant" => "full",
          "strategy" => "null",
          "budget" => 1,
          "selection_seeds" => [101]
        },
        %{
          "model_variant" => "full",
          "strategy" => "cvss",
          "budget" => 1,
          "selection_seeds" => [102]
        }
      ])
      |> put_in(["analysis", "primary_comparisons"], [
        %{
          "strategy" => "cvss",
          "model_variant" => "full",
          "baseline" => "null",
          "baseline_model_variant" => "full",
          "budget" => 1,
          "outcome" => "blast_radius"
        }
      ])
      |> put_in(["evaluation", "trials"], 1)

    {:ok, _manifest} =
      Evaluation.save(%{existing_manifest_id: manifest.id, content: probe})

    assert {:ok, run} = Evaluation.start(manifest_id)
    assert {:ok, completed} = Evaluation.run(run.id)
    assert completed.status == "completed"

    {:ok, files} = NetworkDefense.Evaluation.OutputContract.files(completed)
    files = Map.new(files)

    assert Enum.sort(Map.keys(files)) == Enum.sort(OutputContract.file_names())

    for name <- [
          "graph.json",
          "plans.jsonl",
          "trials.csv",
          "capability_outcomes.csv",
          "summary.csv"
        ] do
      assert Map.has_key?(files, name)
    end

    plans =
      files["plans.jsonl"]
      |> String.trim_trailing()
      |> String.split("\n")

    assert [_, _] = plans

    [_header | trial_rows] = files["trials.csv"] |> String.trim_trailing() |> String.split("\n")
    assert trial_rows != []
  end

  defp run_task do
    Mix.Task.reenable("seed.fixed_order_fulfilment")

    output =
      capture_io(fn ->
        Mix.Tasks.Seed.FixedOrderFulfilment.run([])
      end)

    Jason.decode!(output)
  end
end
