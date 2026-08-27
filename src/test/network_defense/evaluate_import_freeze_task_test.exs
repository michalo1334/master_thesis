defmodule Mix.Tasks.Evaluate.ImportFreezeTest do
  use NetworkDefense.DataCase, async: false

  import ExUnit.CaptureIO

  alias NetworkDefense.Evaluation
  alias NetworkDefense.EvaluationFixtures

  test "imports a versioned manifest file" do
    manifest_id = "import-task-#{System.unique_integer([:positive])}"
    path = manifest_file(manifest_id)

    Mix.Task.reenable("evaluate.import")

    result =
      capture_io(fn ->
        Mix.Tasks.Evaluate.Import.run(["--file", path, "--title", "Imported manifest"])
      end)
      |> Jason.decode!()

    assert result == %{
             "manifest_id" => manifest_id,
             "status" => "imported",
             "title" => "Imported manifest"
           }

    assert %{manifest_id: ^manifest_id, title: "Imported manifest"} =
             Evaluation.get_by_manifest_id(manifest_id)

    File.rm!(path)
  end

  test "rejects a conflicting import and validates required options" do
    manifest_id = "import-conflict-#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "#{manifest_id}.json")
    assert {:ok, _manifest} = EvaluationFixtures.save_manifest(manifest_id)

    File.write!(
      path,
      Jason.encode!(
        EvaluationFixtures.valid_manifest()
        |> Map.put("id", manifest_id)
        |> put_in(["evaluation", "trials"], 11)
      )
    )

    Mix.Task.reenable("evaluate.import")

    assert_raise Mix.Error, "manifest already exists with different content", fn ->
      Mix.Tasks.Evaluate.Import.run(["--file", path])
    end

    Mix.Task.reenable("evaluate.import")

    assert_raise Mix.Error, "missing required option --file", fn ->
      Mix.Tasks.Evaluate.Import.run([])
    end

    File.rm!(path)
  end

  test "freezes a saved topology manifest" do
    manifest_id = "freeze-task-#{System.unique_integer([:positive])}"
    frozen_manifest_id = "#{manifest_id}-frozen"
    assert {:ok, _manifest} = EvaluationFixtures.save_manifest(manifest_id)

    Mix.Task.reenable("evaluate.freeze")

    result =
      capture_io(fn ->
        Mix.Tasks.Evaluate.Freeze.run([
          "--manifest-id",
          manifest_id,
          "--frozen-manifest-id",
          frozen_manifest_id
        ])
      end)
      |> Jason.decode!()

    assert result["source_manifest_id"] == manifest_id
    assert result["target_manifest_id"] == frozen_manifest_id
    assert is_binary(result["graph_revision_id"])
    assert is_binary(result["entry_host_id"])

    assert %{"type" => "graph_revision"} =
             Evaluation.get_by_manifest_id(frozen_manifest_id).content["source"]
  end

  test "requires both freeze identifiers" do
    Mix.Task.reenable("evaluate.freeze")

    assert_raise Mix.Error, "missing required option --manifest-id", fn ->
      Mix.Tasks.Evaluate.Freeze.run([])
    end

    Mix.Task.reenable("evaluate.freeze")

    assert_raise Mix.Error, "missing required option --frozen-manifest-id", fn ->
      Mix.Tasks.Evaluate.Freeze.run(["--manifest-id", "source"])
    end
  end

  defp manifest_file(manifest_id) do
    path = Path.join(System.tmp_dir!(), "#{manifest_id}.json")

    File.write!(
      path,
      Jason.encode!(Map.put(EvaluationFixtures.valid_manifest(), "id", manifest_id))
    )

    path
  end
end
