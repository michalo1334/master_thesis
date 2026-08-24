defmodule NetworkDefense.OutputContractTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.OutputContract
  alias NetworkDefense.EvaluationFixtures
  alias NetworkDefense.Graph.Graphs

  @eval_manifest EvaluationFixtures.analysis_manifest()

  defp run_completed_evaluation do
    manifest_id = "output-contract-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, @eval_manifest, "Output contract")

    assert {:ok, run} = Evaluation.start(manifest_id)
    assert {:ok, completed} = Evaluation.run(run.id)
    assert completed.status == "completed"
    completed
  end

  defp unzip(binary) do
    path =
      Path.join(System.tmp_dir!(), "output-contract-#{System.unique_integer([:positive])}.zip")

    File.write!(path, binary)
    dir = path <> ".d"
    File.mkdir_p!(dir)
    {:ok, _} = :zip.extract(String.to_charlist(path), cwd: String.to_charlist(dir))
    files = File.ls!(dir) |> Map.new(fn name -> {name, File.read!(Path.join(dir, name))} end)
    File.rm_rf!(path)
    File.rm_rf!(dir)
    files
  end

  defp files_map(run) do
    {:ok, files} = OutputContract.files(run)
    Map.new(files)
  end

  test "regenerates the full output contract for a completed run" do
    run = run_completed_evaluation()

    files = files_map(run)
    assert Map.keys(files) |> Enum.sort() == OutputContract.file_names() |> Enum.sort()

    manifest = Jason.decode!(files["manifest.resolved.json"])
    assert get_in(manifest, ["source", "type"]) == "graph_revision"
    assert get_in(manifest, ["source", "graph_revision_id"]) == run.source_graph_revision_id

    graph = Jason.decode!(files["graph.json"])
    assert graph["id"] == Graphs.load_revision(run.source_graph_revision_id).id
    assert is_list(graph["nodes"])
    assert is_list(graph["edges"])

    plans =
      files["plans.jsonl"]
      |> String.trim_trailing()
      |> String.split("\n")
      |> Enum.map(&Jason.decode!/1)

    assert [plan, second_plan] = plans
    assert plan["strategy"] == "cvss"
    assert plan["requested_budget"] == 1
    assert plan["selection_seed"] == 101
    assert plan["action_count"] == length(plan["actions"])

    assert Enum.map(
             plan["actions"],
             &Map.take(&1, ["position", "action_type", "target_id", "cost"])
           ) ==
             plan["actions"]

    assert Enum.map(plan["actions"], & &1["position"]) ==
             plan["actions"] |> Enum.map(& &1["position"]) |> Enum.sort()

    assert second_plan["strategy"] == "simulation_informed"
    assert second_plan["selection_seed"] == 201

    [header | trial_rows] = files["trials.csv"] |> String.trim_trailing() |> String.split("\n")
    assert header == "experiment_id,plan_id,trial_index,seed,blast_radius,mission_impact"
    assert [_, _, _, _, _, _, _, _, _] = trial_rows

    [capability_header | _] =
      files["capability_outcomes.csv"] |> String.trim_trailing() |> String.split("\n")

    assert capability_header ==
             "experiment_id,plan_id,trial_index,seed,capability_id,capability_name,disrupted,impact_weight"

    [summary_header | summary_rows] =
      files["summary.csv"] |> String.trim_trailing() |> String.split("\n")

    assert summary_header ==
             "experiment_id,plan_id,trial_count,expected_blast_radius,median_blast_radius,blast_radius_p95,blast_radius_p99,min_blast_radius,max_blast_radius,runtime_ms"

    assert [_, _, _] = summary_rows

    checksums = files["checksums.txt"] |> String.trim_trailing() |> String.split("\n")
    assert [_, _, _, _, _, _] = checksums

    for {name, content} <- files, name != "checksums.txt" do
      expected = "#{name}  #{:crypto.hash(:sha256, content) |> Base.encode16(case: :lower)}"
      assert expected in checksums
    end
  end

  test "orders graph.json nodes and edges by id regardless of input order" do
    run = run_completed_evaluation()

    graph = Jason.decode!(files_map(run)["graph.json"])

    node_ids = Enum.map(graph["nodes"], & &1["id"])
    edge_ids = Enum.map(graph["edges"], & &1["id"])

    assert node_ids == Enum.sort(node_ids)
    assert edge_ids == Enum.sort(edge_ids)
  end

  test "sorts plans and trial rows deterministically" do
    run = run_completed_evaluation()

    files = files_map(run)
    files_again = files_map(run)

    assert files == files_again

    plans =
      files["plans.jsonl"]
      |> String.trim_trailing()
      |> String.split("\n")
      |> Enum.map(&Jason.decode!/1)

    assert Enum.map(plans, & &1["strategy"]) == ["cvss", "simulation_informed"]

    [_header | trial_rows] = files["trials.csv"] |> String.trim_trailing() |> String.split("\n")

    trial_keys =
      Enum.map(trial_rows, fn row ->
        [experiment_id, _plan_id, trial_index | _] = String.split(row, ",")
        {experiment_id, String.to_integer(trial_index)}
      end)

    assert trial_keys == Enum.sort(trial_keys)
  end

  test "rejects unknown and incomplete runs" do
    assert {:error, :not_found} = OutputContract.files(nil)

    assert {:error, :incomplete} =
             OutputContract.files(%NetworkDefense.Evaluation.EvaluationRun{
               id: Ecto.UUID.generate()
             })

    run = run_completed_evaluation()
    incomplete = %{run | status: "running"}
    assert {:error, :incomplete} = OutputContract.files(incomplete)
  end

  test "archives the output contract as a zip with the expected members" do
    run = run_completed_evaluation()

    assert {:ok, zip_binary, filename} = OutputContract.archive(run)
    assert filename == "evaluation-#{run.id}.zip"
    assert is_binary(zip_binary)

    files = unzip(zip_binary)
    assert Map.keys(files) |> Enum.sort() == OutputContract.file_names() |> Enum.sort()

    files_from_contract = files_map(run)

    for {name, content} <- files_from_contract do
      assert files[name] == content
    end
  end
end
