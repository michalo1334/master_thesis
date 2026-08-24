defmodule NetworkDefense.EvaluationFixtures do
  @moduledoc false

  alias NetworkDefense.Evaluation

  def valid_manifest do
    %{
      "schema_version" => 2,
      "model_version" => "current-model-version",
      "id" => "fixed-enterprise-v1",
      "source" => %{
        "type" => "topology",
        "generator" => "enterprise",
        "hosts" => 8,
        "seed" => 42
      },
      "attacker" => %{
        "entry_host" => %{"type" => "semantic_key", "value" => "internet"},
        "max_attempts" => 1
      },
      "model" => %{
        "objective" => "mission_then_blast_radius",
        "require_pre_attack_feasibility" => true
      },
      "strategy_runs" => [
        %{"strategy" => "null", "budget" => 1, "selection_seeds" => [101]},
        %{"strategy" => "cvss", "budget" => 1, "selection_seeds" => [102]}
      ],
      "analysis" => %{
        "primary_comparisons" => [
          %{
            "strategy" => "cvss",
            "baseline" => "null",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ],
        "confidence_level" => 0.95,
        "bootstrap_resamples" => 100,
        "permutation_resamples" => 100,
        "multiplicity_correction" => "holm",
        "seed" => 9001,
        "pilot" => %{"ci_half_width" => 0.25}
      },
      "evaluation" => %{"trials" => 10, "seed" => 9001}
    }
  end

  def analysis_manifest do
    valid_manifest()
    |> Map.put("strategy_runs", [
      %{"strategy" => "cvss", "budget" => 1, "selection_seeds" => [101]},
      %{"strategy" => "simulation_informed", "budget" => 1, "selection_seeds" => [201]}
    ])
    |> put_in(["analysis", "primary_comparisons"], [
      %{
        "strategy" => "simulation_informed",
        "baseline" => "cvss",
        "budget" => 1,
        "outcome" => "blast_radius"
      }
    ])
    |> put_in(["evaluation", "trials"], 3)
  end

  def save_manifest(id, content \\ valid_manifest(), title \\ "T") do
    Evaluation.save(%{manifest_id: id, title: title, content: Map.put(content, "id", id)})
  end
end
