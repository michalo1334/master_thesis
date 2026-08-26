defmodule NetworkDefense.Evaluation.PlanPreviewTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.PlanPreview

  import NetworkDefense.EvaluationFixtures,
    only: [analysis_manifest: 0, valid_manifest: 0]

  describe "plans/1" do
    test "expands and sorts each strategy run by variant, strategy, budget, and seed" do
      manifest =
        put_in(
          valid_manifest(),
          ["strategy_runs"],
          [
            %{
              "model_variant" => "full",
              "strategy" => "simulation_informed",
              "budget" => 2,
              "selection_seeds" => [201, 203]
            },
            %{
              "model_variant" => "full",
              "strategy" => "null",
              "budget" => 1,
              "selection_seeds" => [301, 302, 303]
            },
            %{
              "model_variant" => "blast_only",
              "strategy" => "null",
              "budget" => 1,
              "selection_seeds" => [101]
            }
          ]
        )

      assert PlanPreview.plans(manifest) == [
               {:blast_only, "null", 1, 101},
               {:full, "null", 1, 301},
               {:full, "null", 1, 302},
               {:full, "null", 1, 303},
               {:full, "simulation_informed", 2, 201},
               {:full, "simulation_informed", 2, 203}
             ]
    end

    test "is stable across repeated calls" do
      assert PlanPreview.plans(valid_manifest()) == PlanPreview.plans(valid_manifest())

      assert PlanPreview.plans(valid_manifest()) == [
               {:full, "cvss", 1, 102},
               {:full, "null", 1, 101}
             ]
    end
  end

  describe "declared?/4 and selection_seeds/4" do
    test "recognizes declared plans and looks up their seeds" do
      assert PlanPreview.declared?(valid_manifest(), "full", "cvss", 1)
      assert PlanPreview.selection_seeds(valid_manifest(), "full", "cvss", 1) == [102]
      refute PlanPreview.declared?(valid_manifest(), "full", "simulation_informed", 1)

      assert PlanPreview.selection_seeds(valid_manifest(), "full", "simulation_informed", 1) ==
               nil
    end
  end

  describe "comparison_groups/1" do
    test "builds tested and baseline groups from a primary comparison" do
      assert [group] = PlanPreview.comparison_groups(valid_manifest())

      assert group == %{
               index: 0,
               tested: %{
                 model_variant: "full",
                 strategy: "cvss",
                 budget: 1,
                 selection_seeds: [102]
               },
               baseline: %{
                 model_variant: "full",
                 strategy: "null",
                 budget: 1,
                 selection_seeds: [101]
               },
               outcome: "blast_radius"
             }
    end

    test "attaches the full declared seed list for each comparison side" do
      manifest =
        put_in(
          valid_manifest(),
          ["strategy_runs"],
          [
            %{
              "model_variant" => "full",
              "strategy" => "simulation_informed",
              "budget" => 1,
              "selection_seeds" => [301, 302, 303]
            },
            %{
              "model_variant" => "blast_only",
              "strategy" => "simulation_informed",
              "budget" => 1,
              "selection_seeds" => [301, 302, 303]
            }
          ]
        )
        |> put_in(["analysis", "primary_comparisons"], [
          %{
            "strategy" => "null",
            "model_variant" => "full",
            "baseline" => "simulation_informed",
            "baseline_model_variant" => "blast_only",
            "budget" => 1,
            "outcome" => "mission_impact"
          },
          %{
            "strategy" => "simulation_informed",
            "model_variant" => "full",
            "baseline" => "simulation_informed",
            "baseline_model_variant" => "blast_only",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ])

      assert PlanPreview.comparison_groups(manifest) == [
               %{
                 index: 0,
                 tested: %{
                   model_variant: "full",
                   strategy: "null",
                   budget: 1,
                   selection_seeds: []
                 },
                 baseline: %{
                   model_variant: "blast_only",
                   strategy: "simulation_informed",
                   budget: 1,
                   selection_seeds: [301, 302, 303]
                 },
                 outcome: "mission_impact"
               },
               %{
                 index: 1,
                 tested: %{
                   model_variant: "full",
                   strategy: "simulation_informed",
                   budget: 1,
                   selection_seeds: [301, 302, 303]
                 },
                 baseline: %{
                   model_variant: "blast_only",
                   strategy: "simulation_informed",
                   budget: 1,
                   selection_seeds: [301, 302, 303]
                 },
                 outcome: "blast_radius"
               }
             ]
    end
  end

  describe "Evaluation.describe_manifest/1" do
    test "returns wire-compatible plans and comparison groups for a valid manifest" do
      assert {:ok, description} = Evaluation.describe_manifest(analysis_manifest())

      assert description["plans"] == [
               %{
                 "model_variant" => "full",
                 "strategy" => "cvss",
                 "budget" => 1,
                 "selection_seed" => 101
               },
               %{
                 "model_variant" => "full",
                 "strategy" => "simulation_informed",
                 "budget" => 1,
                 "selection_seed" => 201
               }
             ]

      assert description["comparison_groups"] == [
               %{
                 "index" => 0,
                 "tested" => %{
                   "model_variant" => "full",
                   "strategy" => "simulation_informed",
                   "budget" => 1,
                   "selection_seeds" => [201]
                 },
                 "baseline" => %{
                   "model_variant" => "full",
                   "strategy" => "cvss",
                   "budget" => 1,
                   "selection_seeds" => [101]
                 },
                 "outcome" => "blast_radius"
               }
             ]
    end

    test "returns existing validation errors for an invalid manifest" do
      assert {:error, errors} = Evaluation.describe_manifest(%{"bad" => 1})
      assert Enum.any?(errors, &(&1.path == "schema_version"))
    end

    test "rejects a value that is not a JSON object" do
      assert {:error, [%{path: "content", message: "must be a JSON object"}]} =
               Evaluation.describe_manifest(nil)
    end
  end
end
