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
