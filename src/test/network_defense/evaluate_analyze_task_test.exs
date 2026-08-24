defmodule Mix.Tasks.Evaluate.AnalyzeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias NetworkDefense.Evaluation

  setup do
    :meck.new(Evaluation, [:passthrough])
    on_exit(fn -> :meck.unload() end)
  end

  test "writes the validated result and reports its digest" do
    output = Path.join(System.tmp_dir!(), "analysis-#{System.unique_integer([:positive])}.zip")
    :meck.expect(Evaluation, :analyze, fn "run-123", "pilot" -> {:ok, "result-zip"} end)
    Mix.Task.reenable("evaluate.analyze")

    response =
      capture_io(fn ->
        Mix.Tasks.Evaluate.Analyze.run([
          "--run-id",
          "run-123",
          "--mode",
          "pilot",
          "--output",
          output
        ])
      end)
      |> Jason.decode!()

    assert File.read!(output) == "result-zip"
    assert response["run_id"] == "run-123"
    assert response["mode"] == "pilot"
    assert response["path"] == output
    assert response["byte_size"] == 10
    assert response["sha256"] == Base.encode16(:crypto.hash(:sha256, "result-zip"), case: :lower)

    File.rm!(output)
  end

  test "validates required options and mode" do
    Mix.Task.reenable("evaluate.analyze")

    assert_raise Mix.Error, "missing required option --run-id", fn ->
      Mix.Tasks.Evaluate.Analyze.run([])
    end

    Mix.Task.reenable("evaluate.analyze")

    assert_raise Mix.Error, "mode must be pilot or analyze", fn ->
      Mix.Tasks.Evaluate.Analyze.run([
        "--run-id",
        "run",
        "--mode",
        "unknown",
        "--output",
        "result.zip"
      ])
    end
  end
end
