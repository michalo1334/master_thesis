defmodule Mix.Tasks.Evaluate.ManifestTest do
  use NetworkDefense.DataCase, async: true

  import ExUnit.CaptureIO

  alias NetworkDefense.Evaluation

  @manifest %{
    "schema_version" => 1,
    "model_version" => "current-model-version",
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
    "evaluation" => %{"trials" => 1, "seed" => 9001}
  }

  test "runs a saved manifest" do
    manifest_id = "cli-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             Evaluation.save(%{
               manifest_id: manifest_id,
               title: "CLI manifest",
               content: Map.put(@manifest, "id", manifest_id)
             })

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

  test "requires a manifest id" do
    assert_raise Mix.Error, "missing required option --manifest-id", fn ->
      Mix.Tasks.Evaluate.Manifest.run([])
    end
  end
end
