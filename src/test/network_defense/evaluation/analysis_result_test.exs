defmodule NetworkDefense.Evaluation.AnalysisResultTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.AnalysisResult

  test "parses the required analysis members" do
    assert {:ok, result} =
             AnalysisResult.parse(
               zip(%{"metadata.json" => metadata(), "analysis.json" => analysis()}),
               10_000
             )

    assert result.metadata["manifest_id"] == "manifest"
    assert result.primary_results == []
    assert result.feasibility_summary == [feasibility_row()]
  end

  test "parses a baseline feasibility row with an empty plan ID" do
    analysis = analysis(%{"feasibility_summary" => [%{feasibility_row() | "plan_id" => ""}]})

    assert {:ok, result} =
             AnalysisResult.parse(
               zip(%{"metadata.json" => metadata(), "analysis.json" => analysis}),
               10_000
             )

    assert [%{"plan_id" => ""}] = result.feasibility_summary
  end

  test "accepts string, null, and missing capability names" do
    row = capability_row()

    for capability_row <- [
          row,
          Map.put(row, "capability_name", nil),
          Map.delete(row, "capability_name")
        ] do
      analysis =
        Jason.encode!(%{
          "primary_results" => [],
          "secondary_results" => [],
          "capability_results" => [capability_row],
          "feasibility_summary" => [feasibility_row()]
        })

      assert {:ok, _result} =
               AnalysisResult.parse(
                 zip(%{"metadata.json" => metadata(), "analysis.json" => analysis}),
                 10_000
               )
    end

    assert row["capability_name"] == "Capability"
  end

  test "rejects a non-string, non-null capability name" do
    analysis =
      Jason.encode!(%{
        "primary_results" => [],
        "secondary_results" => [],
        "capability_results" => [%{capability_row() | "capability_name" => 1}],
        "feasibility_summary" => [feasibility_row()]
      })

    assert {:error, :malformed_row} =
             AnalysisResult.parse(
               zip(%{"metadata.json" => metadata(), "analysis.json" => analysis}),
               10_000
             )
  end

  defp capability_row do
    %{
      "comparison" => 0,
      "strategy" => "tested",
      "model_variant" => "full",
      "baseline" => "baseline",
      "baseline_model_variant" => "full",
      "budget" => 1,
      "capability_id" => "capability",
      "capability_name" => "Capability",
      "tested_probability" => 0.5,
      "baseline_probability" => 0.5,
      "probability_difference" => 0.0,
      "ci_lower" => 0.0,
      "ci_upper" => 0.0,
      "ci_half_width" => 0.0
    }
  end

  test "parses result rows with model variants" do
    analysis =
      Jason.encode!(%{
        "primary_results" => [primary_row()],
        "secondary_results" => [secondary_row()],
        "capability_results" => [capability_row()],
        "feasibility_summary" => [feasibility_row()]
      })

    assert {:ok, result} =
             AnalysisResult.parse(
               zip(%{"metadata.json" => metadata(), "analysis.json" => analysis}),
               10_000
             )

    assert [%{"model_variant" => "full", "baseline_model_variant" => "blast_only_unconstrained"}] =
             result.primary_results
  end

  test "requires model variants on every result row" do
    for {key, row} <- [
          {"primary_results", Map.delete(primary_row(), "model_variant")},
          {"primary_results", Map.delete(primary_row(), "baseline_model_variant")},
          {"secondary_results", Map.delete(secondary_row(), "model_variant")},
          {"secondary_results", Map.delete(secondary_row(), "baseline_model_variant")},
          {"capability_results", Map.delete(capability_row(), "model_variant")},
          {"capability_results", Map.delete(capability_row(), "baseline_model_variant")}
        ] do
      analysis =
        Jason.encode!(%{
          "primary_results" => [],
          "secondary_results" => [],
          "capability_results" => [],
          "feasibility_summary" => [feasibility_row()],
          key => [row]
        })

      assert {:error, :malformed_row} =
               AnalysisResult.parse(
                 zip(%{"metadata.json" => metadata(), "analysis.json" => analysis}),
                 10_000
               )
    end
  end

  test "rejects a non-string model variant" do
    analysis =
      Jason.encode!(%{
        "primary_results" => [%{primary_row() | "model_variant" => 1}],
        "secondary_results" => [],
        "capability_results" => [],
        "feasibility_summary" => [feasibility_row()]
      })

    assert {:error, :malformed_row} =
             AnalysisResult.parse(
               zip(%{"metadata.json" => metadata(), "analysis.json" => analysis}),
               10_000
             )
  end

  test "parses a study analysis result with every new field present" do
    assert {:ok, result} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" => study_metadata("study-analyze"),
                 "primary_results.json" => Jason.encode!([study_primary_row()])
               }),
               10_000
             )

    assert result.metadata["family_scope"] == "study"
    assert result.metadata["family_size"] == 36
    assert [%{"tier" => "small", "comparison_id" => _id}] = result.primary_results
    assert result.pilot_results == []
  end

  test "parses a study pilot result with every new field present" do
    assert {:ok, result} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" => study_metadata("study-pilot"),
                 "pilot_results.json" => Jason.encode!([study_pilot_row()])
               }),
               10_000
             )

    assert result.metadata["recommended_plan_selection_seed_count"] == 6
    assert result.metadata["recommended_attacks_per_plan"] == 12
    assert result.metadata["insufficient_pilot"] == false
    assert [%{"tier" => "small", "guarded_ci_half_width" => 0.5}] = result.pilot_results
    assert result.primary_results == []
  end

  test "accepts missing new fields in legacy results" do
    assert {:ok, result} =
             AnalysisResult.parse(
               zip(%{"metadata.json" => metadata(), "analysis.json" => analysis()}),
               10_000
             )

    assert result.metadata["manifest_id"] == "manifest"
    assert result.pilot_results == []
    assert result.primary_results == []
  end

  test "rejects wrong study field types" do
    assert {:error, :malformed_row} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" => study_metadata("study-analyze"),
                 "primary_results.json" => Jason.encode!([%{study_primary_row() | "tier" => 1}])
               }),
               10_000
             )

    assert {:error, :malformed_row} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" => study_metadata("study-pilot"),
                 "pilot_results.json" =>
                   Jason.encode!([%{study_pilot_row() | "informative" => "yes"}])
               }),
               10_000
             )

    assert {:error, :malformed_field} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" =>
                   Jason.encode!(Map.put(study_metadata_map("study-pilot"), "family_size", "36")),
                 "pilot_results.json" => Jason.encode!([study_pilot_row()])
               }),
               10_000
             )

    assert {:error, :malformed_field} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" =>
                   Jason.encode!(
                     Map.put(study_metadata_map("study-pilot"), "insufficient_pilot", "no")
                   ),
                 "pilot_results.json" => Jason.encode!([study_pilot_row()])
               }),
               10_000
             )
  end

  test "rejects a study result whose command mode does not match its members" do
    assert {:error, :malformed_field} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" => study_metadata("pilot"),
                 "primary_results.json" => Jason.encode!([study_primary_row()])
               }),
               10_000
             )

    assert {:error, :malformed_field} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" => study_metadata("analyze"),
                 "pilot_results.json" => Jason.encode!([study_pilot_row()])
               }),
               10_000
             )
  end

  test "rejects an incomplete study bundle" do
    assert {:error, :missing_or_duplicate} =
             AnalysisResult.parse(
               zip(%{"study_metadata.json" => study_metadata("study-pilot")}),
               10_000
             )

    assert {:error, :missing_or_duplicate} =
             AnalysisResult.parse(
               zip(%{
                 "study_metadata.json" => study_metadata("study-analyze"),
                 "primary_results.json" => "[]",
                 "pilot_results.json" => "[]"
               }),
               10_000
             )
  end

  test "requires the metadata model variants list" do
    for metadata <- [
          Jason.encode!(%{
            "manifest_id" => "manifest",
            "schema_version" => 3,
            "model_version" => "model",
            "command_mode" => "analyze"
          }),
          Jason.encode!(%{
            "manifest_id" => "manifest",
            "schema_version" => 3,
            "model_version" => "model",
            "model_variants" => "full",
            "command_mode" => "analyze"
          })
        ] do
      assert {:error, :malformed_field} =
               AnalysisResult.parse(
                 zip(%{"metadata.json" => metadata, "analysis.json" => analysis()}),
                 10_000
               )
    end
  end

  test "rejects malformed Phase 1 summaries" do
    invalid_feasibility = %{"pre_attack_feasible" => "yes"}
    invalid_runtime = %{"evaluator_runtime_ms" => -1}

    assert {:error, :malformed_row} =
             AnalysisResult.parse(
               zip(%{
                 "metadata.json" => metadata(),
                 "analysis.json" =>
                   analysis(%{
                     "feasibility_summary" => [Map.merge(feasibility_row(), invalid_feasibility)]
                   })
               }),
               10_000
             )

    assert {:error, :malformed_runtime_summary} =
             AnalysisResult.parse(
               zip(%{
                 "metadata.json" => metadata(invalid_runtime),
                 "analysis.json" => analysis()
               }),
               10_000
             )
  end

  defp primary_row do
    %{
      "comparison" => 0,
      "strategy" => "simulation_informed",
      "model_variant" => "full",
      "baseline" => "cvss",
      "baseline_model_variant" => "blast_only_unconstrained",
      "budget" => 2,
      "outcome" => "blast_radius",
      "paired_mean_difference" => 0.0,
      "ci_lower" => 0.0,
      "ci_upper" => 0.0,
      "ci_half_width" => 0.0,
      "d_z" => 0.0,
      "p_raw" => 1.0,
      "p_adjusted" => 1.0
    }
  end

  defp secondary_row do
    %{
      "comparison" => 0,
      "strategy" => "simulation_informed",
      "model_variant" => "full",
      "baseline" => "cvss",
      "baseline_model_variant" => "blast_only_unconstrained",
      "budget" => 2,
      "outcome" => "mission_impact",
      "mean_difference" => 0.0,
      "ci_lower" => 0.0,
      "ci_upper" => 0.0,
      "ci_half_width" => 0.0
    }
  end

  test "rejects missing, duplicate, malformed, and oversized members" do
    archive = zip(%{"metadata.json" => metadata()})
    assert {:error, :missing_or_duplicate} = AnalysisResult.parse(archive, 10_000)

    duplicate =
      :zip.create(
        ~c"analysis.zip",
        [
          {~c"metadata.json", metadata()},
          {~c"metadata.json", metadata()},
          {~c"analysis.json", analysis()}
        ],
        [:memory]
      )

    {:ok, {_, duplicate_zip}} = duplicate
    assert {:error, :missing_or_duplicate} = AnalysisResult.parse(duplicate_zip, 10_000)

    malformed = zip(%{"metadata.json" => "{}", "analysis.json" => "not json"})
    assert {:error, {:malformed, "analysis.json"}} = AnalysisResult.parse(malformed, 10_000)

    oversized = zip(%{"metadata.json" => metadata(), "analysis.json" => analysis() <> " "})
    assert {:error, :member_too_large} = AnalysisResult.parse(oversized, 1)
  end

  defp metadata(runtime_summary \\ %{}) do
    Jason.encode!(%{
      "manifest_id" => "manifest",
      "schema_version" => 3,
      "model_version" => "model",
      "model_variants" => [%{"id" => "full", "objective" => "mission_then_blast_radius"}],
      "command_mode" => "analyze",
      "runtime_summary" =>
        Map.merge(
          %{
            "median_plan_selection_runtime_ms" => 1.0,
            "median_simulation_runtime_ms" => 2.0,
            "evaluator_runtime_ms" => 3.0
          },
          runtime_summary
        )
    })
  end

  defp analysis(overrides \\ %{}) do
    %{
      "primary_results" => [],
      "secondary_results" => [],
      "capability_results" => [],
      "feasibility_summary" => [feasibility_row()]
    }
    |> Map.merge(overrides)
    |> Jason.encode!()
  end

  defp feasibility_row do
    %{
      "experiment_id" => "experiment",
      "plan_id" => "plan",
      "pre_attack_feasible" => true,
      "unavailable_required_flow_count" => 0,
      "affected_capability_count" => 0
    }
  end

  defp study_metadata(mode), do: Jason.encode!(study_metadata_map(mode))

  defp study_metadata_map(mode) do
    %{
      "study_id" => "study-1",
      "specification_version" => 2,
      "family_scope" => "study",
      "family_size" => 36,
      "command_mode" => mode,
      "multiplicity_correction" => "holm",
      "expected_family" => %{
        "strategies" => ["simulation_informed"],
        "baseline" => "cvss",
        "budgets" => [1, 2, 3],
        "outcome" => "mission_impact"
      },
      "tier_labels" => ["small", "medium", "large"],
      "uncertainty_sources" => ["plan_selection", "attack_outcome"],
      "recommended_plan_selection_seed_count" => 6,
      "recommended_attacks_per_plan" => 12,
      "insufficient_pilot" => false
    }
  end

  defp study_primary_row do
    %{
      "comparison" => 0,
      "comparison_id" => "small|full|simulation_informed|cvss|1|mission_impact",
      "tier" => "small",
      "strategy" => "simulation_informed",
      "model_variant" => "full",
      "baseline" => "cvss",
      "baseline_model_variant" => "full",
      "budget" => 1,
      "outcome" => "mission_impact",
      "informative" => true,
      "tested_plan_count" => 6,
      "baseline_plan_count" => 6,
      "attacks_per_plan" => 12,
      "paired_mean_difference" => 0.0,
      "ci_lower" => 0.0,
      "ci_upper" => 0.0,
      "ci_half_width" => 0.0,
      "d_z" => nil,
      "p_raw" => 1.0,
      "p_adjusted" => 1.0
    }
  end

  defp study_pilot_row do
    %{
      "comparison_id" => "small|full|simulation_informed|cvss|1|mission_impact",
      "tier" => "small",
      "informative" => true,
      "candidate_plan_count" => 6,
      "candidate_attacks_per_plan" => 12,
      "guarded_ci_half_width" => 0.5,
      "target" => 1.0,
      "passes" => true
    }
  end

  defp zip(files) do
    entries = Enum.map(files, fn {name, content} -> {String.to_charlist(name), content} end)
    {:ok, {_, archive}} = :zip.create(~c"analysis.zip", entries, [:memory])
    archive
  end
end
