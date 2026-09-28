defmodule Mix.Tasks.Evaluate.AnalyzeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Error
  alias Mix.Task
  alias Mix.Tasks.Evaluate.Analyze
  alias NetworkDefense.Evaluation

  setup do
    :meck.new(Evaluation, [:passthrough])
    on_exit(fn -> :meck.unload() end)
  end

  test "writes the validated result and reports its digest" do
    output = Path.join(System.tmp_dir!(), "analysis-#{System.unique_integer([:positive])}.zip")
    :meck.expect(Evaluation, :analyze, fn "run-123" -> {:ok, "result-zip"} end)
    Task.reenable("evaluate.analyze")

    response =
      capture_io(fn ->
        Analyze.run([
          "--run-id",
          "run-123",
          "--output",
          output
        ])
      end)
      |> Jason.decode!()

    assert File.read!(output) == "result-zip"
    assert response["run_id"] == "run-123"
    assert response["path"] == output
    assert response["byte_size"] == 10
    assert response["sha256"] == Base.encode16(:crypto.hash(:sha256, "result-zip"), case: :lower)
    refute Map.has_key?(response, "mode")

    File.rm!(output)
  end

  test "validates required options and rejects the removed mode option" do
    Task.reenable("evaluate.analyze")

    assert_raise Error, "missing required option --run-id", fn ->
      Analyze.run([])
    end

    Task.reenable("evaluate.analyze")

    assert_raise Error, "invalid options: analyze, --mode", fn ->
      Analyze.run([
        "--run-id",
        "run",
        "--mode",
        "analyze",
        "--output",
        "result.zip"
      ])
    end
  end
end
