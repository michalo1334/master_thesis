defmodule NetworkDefense.EvaluationFixtures do
  @moduledoc false

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Optimization.{ModelVariant, SimulationObjective}

  def valid_manifest do
    %{
      "schema_version" => 3,
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
      "model_variants" => [
        %{
          "id" => "full",
          "objective" => "mission_then_blast_radius",
          "require_pre_attack_feasibility" => true
        }
      ],
      "strategy_runs" => [
        %{
          "model_variant" => "full",
          "strategy" => "null",
          "budget" => 1,
          "selection_seeds" => [101]
        },
        %{
          "model_variant" => "full",
          "strategy" => "cvss",
          "budget" => 1,
          "selection_seeds" => [102]
        }
      ],
      "analysis" => %{
        "primary_comparisons" => [
          %{
            "strategy" => "cvss",
            "model_variant" => "full",
            "baseline" => "null",
            "baseline_model_variant" => "full",
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
      %{
        "model_variant" => "full",
        "strategy" => "cvss",
        "budget" => 1,
        "selection_seeds" => [101]
      },
      %{
        "model_variant" => "full",
        "strategy" => "simulation_informed",
        "budget" => 1,
        "selection_seeds" => [201]
      }
    ])
    |> put_in(["analysis", "primary_comparisons"], [
      %{
        "strategy" => "simulation_informed",
        "model_variant" => "full",
        "baseline" => "cvss",
        "baseline_model_variant" => "full",
        "budget" => 1,
        "outcome" => "blast_radius"
      }
    ])
    |> put_in(["evaluation", "trials"], 3)
  end

  def two_variant_manifest do
    valid_manifest()
    |> put_in(["model_variants"], [
      %{
        "id" => "full",
        "objective" => "mission_then_blast_radius",
        "require_pre_attack_feasibility" => true
      },
      %{
        "id" => "mission_only",
        "objective" => "mission_impact_only",
        "require_pre_attack_feasibility" => true
      }
    ])
    |> Map.put("strategy_runs", [
      %{
        "model_variant" => "full",
        "strategy" => "null",
        "budget" => 1,
        "selection_seeds" => [101]
      },
      %{
        "model_variant" => "full",
        "strategy" => "cvss",
        "budget" => 1,
        "selection_seeds" => [102]
      },
      %{
        "model_variant" => "mission_only",
        "strategy" => "null",
        "budget" => 1,
        "selection_seeds" => [101]
      },
      %{
        "model_variant" => "mission_only",
        "strategy" => "cvss",
        "budget" => 1,
        "selection_seeds" => [102]
      }
    ])
  end

  def canonical_variants do
    Enum.map(ModelVariant.values(), fn variant ->
      definition = ModelVariant.definition(variant)

      %{
        "id" => ModelVariant.to_wire(variant),
        "objective" => SimulationObjective.to_wire(definition.objective),
        "require_pre_attack_feasibility" => definition.require_pre_attack_feasibility
      }
    end)
  end

  def save_manifest(id, content \\ valid_manifest(), title \\ "T") do
    attrs = %{manifest_id: id, title: title, content: Map.put(content, "id", id)}

    case Evaluation.get_by_manifest_id(id) do
      nil -> Evaluation.save(attrs)
      manifest -> Evaluation.save(Map.put(attrs, :existing_manifest_id, manifest.id))
    end
  end
end
