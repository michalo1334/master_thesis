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
          "capability_results" => [capability_row]
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
        "capability_results" => [%{capability_row() | "capability_name" => 1}]
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
      "baseline" => "baseline",
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

  defp metadata do
    Jason.encode!(%{
      "manifest_id" => "manifest",
      "schema_version" => 2,
      "model_version" => "model",
      "command_mode" => "pilot",
      "pilot_comparison_pass" => []
    })
  end

  defp analysis do
    Jason.encode!(%{
      "primary_results" => [],
      "secondary_results" => [],
      "capability_results" => []
    })
  end

  defp zip(files) do
    entries = Enum.map(files, fn {name, content} -> {String.to_charlist(name), content} end)
    {:ok, {_, archive}} = :zip.create(~c"analysis.zip", entries, [:memory])
    archive
  end
end
