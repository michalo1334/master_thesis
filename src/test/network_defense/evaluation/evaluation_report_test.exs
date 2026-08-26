defmodule NetworkDefense.Evaluation.EvaluationReportTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.EvaluationReport
  alias NetworkDefense.EvaluationFixtures

  @eval_manifest EvaluationFixtures.analysis_manifest()

  defp run_completed_evaluation do
    manifest_id = "eval-report-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, @eval_manifest, "Report manifest")

    assert {:ok, run} = Evaluation.start(manifest_id)
    assert {:ok, completed} = Evaluation.run(run.id)
    assert completed.status == "completed"
    completed
  end

  test "projects manifest, source, status, plans, and aggregate results" do
    run = run_completed_evaluation()

    report = Evaluation.report(run.id)
    assert report.run_id == run.id
    assert report.status == "completed"
    assert String.starts_with?(report.manifest_id, "eval-report-")
    assert report.manifest_title == "Report manifest"
    assert report.source_graph_revision_id == run.source_graph_revision_id
    assert is_binary(report.source_graph_title)

    assert [
             %{
               id: cvss_plan_id,
               model_variant: "full",
               strategy: "cvss",
               requested_budget: 1,
               selection_seed: 101,
               status: "completed",
               action_count: action_count
             },
             %{
               id: simulation_plan_id,
               model_variant: "full",
               strategy: "simulation_informed",
               selection_seed: 201
             }
           ] = report.plans

    assert is_integer(action_count)

    assert [
             %{
               optimization_run_id: nil,
               trial_count: 3,
               expected_blast_radius: expected_blast_radius,
               median_blast_radius: median_blast_radius
             },
             %{optimization_run_id: experiment_plan_id_a, trial_count: 3},
             %{optimization_run_id: experiment_plan_id_b, trial_count: 3}
           ] = report.experiments

    assert Enum.sort([experiment_plan_id_a, experiment_plan_id_b]) ==
             Enum.sort([cvss_plan_id, simulation_plan_id])

    assert is_float(expected_blast_radius)
    assert is_integer(median_blast_radius)
  end

  test "emits assembly progress through the callback" do
    run = run_completed_evaluation()

    report =
      Evaluation.report(run.id, fn graph_id, graph_revision_id, completed, total, detail ->
        send(self(), {graph_id, graph_revision_id, completed, total, detail})
        :ok
      end)

    assert is_map(report)

    steps = for _ <- 1..4, do: receive(do: (msg -> msg))

    assert Enum.any?(steps, fn {graph_id, graph_revision_id, c, t, d} ->
             graph_id == report.graph_id and
               graph_revision_id == report.source_graph_revision_id and
               {c, t, d} == {1, 5, "Loading source graph"}
           end)

    assert Enum.any?(steps, fn {_, _, c, t, d} ->
             {c, t, d} == {2, 5, "Summarizing plans"}
           end)

    assert Enum.any?(steps, fn {_, _, c, t, d} ->
             {c, t, d} == {3, 5, "Aggregating experiment 1 of 3"}
           end)

    assert Enum.any?(steps, fn {_, _, c, t, d} ->
             {c, t, d} == {4, 5, "Aggregating experiment 2 of 3"}
           end)
  end

  test "returns nil for an unknown run" do
    assert Evaluation.report(Ecto.UUID.generate()) == nil
  end

  test "returns nil when the source graph cannot be loaded" do
    run = %NetworkDefense.Evaluation.EvaluationRun{
      id: Ecto.UUID.generate(),
      source_graph_revision_id: Ecto.UUID.generate(),
      status: "running",
      evaluation_manifest: %NetworkDefense.Evaluation.EvaluationManifest{
        manifest_id: "m",
        title: "T"
      }
    }

    assert EvaluationReport.generate(run) == nil
  end

  test "reports a failed run with its failure reason" do
    manifest_id = "eval-report-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, @eval_manifest, "Report manifest")

    assert {:ok, run} = Evaluation.start(manifest_id)
    assert {:ok, failed} = NetworkDefense.Evaluation.EvaluationRuns.fail(run, "boom")

    report = Evaluation.report(failed.id)
    assert report.status == "failed"
    assert report.failure_reason == "boom"
  end
end
