defmodule NetworkDefense.EvaluationReportTest do
  use NetworkDefense.DataCase, async: true

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.EvaluationReport

  @eval_manifest %{
    "schema_version" => 1,
    "model_version" => "current-model-version",
    "id" => "eval-report-v1",
    "source" => %{"type" => "topology", "generator" => "enterprise", "hosts" => 8, "seed" => 42},
    "attacker" => %{
      "entry_host" => %{"type" => "semantic_key", "value" => "internet"},
      "max_attempts" => 1
    },
    "model" => %{
      "objective" => "mission_then_blast_radius",
      "require_pre_attack_feasibility" => true
    },
    "budgets" => [1],
    "strategies" => ["null"],
    "selection_seeds" => [101],
    "evaluation" => %{"trials" => 3, "seed" => 9001}
  }

  defp run_completed_evaluation do
    manifest_id = "eval-report-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             Evaluation.save(%{
               manifest_id: manifest_id,
               title: "Report manifest",
               content: Map.put(@eval_manifest, "id", manifest_id)
             })

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

    assert [plan] = report.plans
    assert plan.strategy == "null"
    assert plan.requested_budget == 1
    assert plan.selection_seed == 101
    assert plan.status == "completed"
    assert is_integer(plan.action_count)

    assert [baseline, post_defense] = report.experiments
    assert baseline.optimization_run_id == nil
    assert post_defense.optimization_run_id == plan.id
    assert baseline.trial_count == 3
    assert post_defense.trial_count == 3
    assert is_float(baseline.expected_blast_radius)
    assert is_integer(baseline.median_blast_radius)
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
               {c, t, d} == {1, 4, "Loading source graph"}
           end)

    assert Enum.any?(steps, fn {_, _, c, t, d} ->
             {c, t, d} == {2, 4, "Summarizing plans"}
           end)

    assert Enum.any?(steps, fn {_, _, c, t, d} ->
             {c, t, d} == {3, 4, "Aggregating experiment 1 of 2"}
           end)

    assert Enum.any?(steps, fn {_, _, c, t, d} ->
             {c, t, d} == {4, 4, "Aggregating experiment 2 of 2"}
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
             Evaluation.save(%{
               manifest_id: manifest_id,
               title: "Report manifest",
               content: Map.put(@eval_manifest, "id", manifest_id)
             })

    assert {:ok, run} = Evaluation.start(manifest_id)
    assert {:ok, failed} = NetworkDefense.Evaluation.EvaluationRuns.fail(run, "boom")

    report = Evaluation.report(failed.id)
    assert report.status == "failed"
    assert report.failure_reason == "boom"
  end
end
