defmodule Mix.Tasks.Evaluate.ManifestTest do
  use NetworkDefense.DataCase, async: false

  import ExUnit.CaptureIO

  alias NetworkDefense.EvaluationFixtures

  @manifest EvaluationFixtures.analysis_manifest() |> put_in(["evaluation", "trials"], 1)

  test "runs a saved manifest" do
    manifest_id = "cli-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, @manifest, "CLI manifest")

    Mix.Task.reenable("evaluate.manifest")

    output =
      capture_io(fn ->
        Mix.Tasks.Evaluate.Manifest.run(["--manifest-id", manifest_id])
      end)

    assert %{
             "evaluation_run_id" => run_id,
             "manifest_id" => ^manifest_id,
             "status" => "completed"
           } = Jason.decode!(output)

    assert is_binary(run_id)
  end

  test "writes a completed output contract for offline analysis" do
    manifest_id = "cli-output-#{System.unique_integer([:positive])}"
    output = Path.join(System.tmp_dir!(), "#{manifest_id}.zip")

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, @manifest, "CLI output manifest")

    Mix.Task.reenable("evaluate.manifest")

    capture_io(fn ->
      Mix.Tasks.Evaluate.Manifest.run([
        "--manifest-id",
        manifest_id,
        "--output",
        output
      ])
    end)

    assert File.exists?(output)
    assert {:ok, members} = :zip.list_dir(String.to_charlist(output))
    assert Enum.any?(members, &match?({:zip_file, ~c"manifest.resolved.json", _, _, _, _}, &1))

    File.rm!(output)
  end

  test "requires a manifest id" do
    assert_raise Mix.Error, "missing required option --manifest-id", fn ->
      Mix.Tasks.Evaluate.Manifest.run([])
    end
  end
end
