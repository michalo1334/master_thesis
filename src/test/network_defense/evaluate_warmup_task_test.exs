defmodule Mix.Tasks.Evaluate.WarmupTest do
  use NetworkDefense.DataCase, async: false

  import ExUnit.CaptureIO

  alias NetworkDefense.EvaluationFixtures

  @manifest EvaluationFixtures.analysis_manifest() |> put_in(["evaluation", "trials"], 1)

  test "runs a saved manifest as a warm-up" do
    manifest_id = "cli-warmup-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, @manifest, "CLI warm-up manifest")

    Mix.Task.reenable("evaluate.warmup")

    output =
      capture_io(fn ->
        Mix.Tasks.Evaluate.Warmup.run(["--manifest-id", manifest_id])
      end)

    assert %{
             "evaluation_run_id" => run_id,
             "manifest_id" => ^manifest_id,
             "purpose" => "warmup",
             "status" => "completed"
           } = Jason.decode!(output)

    assert is_binary(run_id)
  end

  test "requires a manifest id" do
    assert_raise Mix.Error, "missing required option --manifest-id", fn ->
      Mix.Tasks.Evaluate.Warmup.run([])
    end
  end
end
