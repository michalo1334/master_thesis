defmodule NetworkDefense.Evaluation.EndToEndRehearsalTest do
  @moduledoc """
  Cross-language rehearsal of the crossed study boundary.

  The test builds deterministic synthetic tier archives through the Python
  harness, assembles the outer study ZIP through `StudyBundle.archive/2`,
  runs `/v1/study/pilot` and `/v1/study/analyze` on those exact bytes, and
  parses both results through `AnalysisResult.parse/2` and the Phoenix
  contracts. It records the evidence under a temporary directory.

  This test shells out to `uv` and the analysis service. It is tagged
  `:rehearsal` and excluded from the default suite. Run it with:

      mix test --include rehearsal \
        test/network_defense/evaluation/end_to_end_rehearsal_test.exs
  """

  use ExUnit.Case, async: false

  @moduletag :rehearsal
  @moduletag timeout: 900_000

  alias NetworkDefense.Evaluation.{AnalysisResult, StudyBundle}

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.{
    EvaluationAnalysisMetadata,
    EvaluationAnalysisPilotRow,
    EvaluationAnalysisPrimaryRow
  }

  @family_size 36
  @candidate_count 4
  @max_result_bytes 50_000_000
  @evidence_dir "crossed-study-rehearsal"

  setup_all do
    %{uv: System.find_executable("uv"), analysis_dir: analysis_dir()}
  end

  test "rehearses the crossed study boundary end to end", %{uv: uv, analysis_dir: analysis_dir} do
    assert is_binary(uv), "uv is required; install it and run uv sync in evaluation/analysis"
    assert File.dir?(analysis_dir), "analysis directory is missing: #{analysis_dir}"

    evidence = Path.join(System.tmp_dir!(), @evidence_dir)
    File.rm_rf!(evidence)
    File.mkdir_p!(evidence)
    fixtures_dir = Path.join(evidence, "fixtures")
    fixture_args = ["fixtures", "--output", fixtures_dir]

    fixture_manifest = run_harness(uv, analysis_dir, fixture_args)
    spec = fixture_manifest["study_spec"] |> File.read!() |> Jason.decode!()
    labels = fixture_manifest["labels"]

    assert_disjoint_schedules(spec, fixture_manifest["seeds"])

    pilot_entries = tier_entries(fixture_manifest["pilot_tiers"], labels, :pilot)
    final_entries = tier_entries(fixture_manifest["final_tiers"], labels, :final)

    assert {:ok, pilot_bundle} = StudyBundle.archive(pilot_entries, spec)
    assert {:ok, final_bundle} = StudyBundle.archive(final_entries, spec)

    pilot_path = Path.join(evidence, "pilot-study.zip")
    final_path = Path.join(evidence, "final-study.zip")
    File.write!(pilot_path, pilot_bundle)
    File.write!(final_path, final_bundle)

    routes_dir = Path.join(evidence, "routes")

    routes_args = [
      "run",
      "--pilot-bundle",
      pilot_path,
      "--final-bundle",
      final_path,
      "--output",
      routes_dir
    ]

    run_harness(uv, analysis_dir, routes_args)

    pilot_zip = File.read!(Path.join(routes_dir, "pilot-output.zip"))
    final_zip = File.read!(Path.join(routes_dir, "final-output.zip"))

    assert {:ok, pilot_document} = AnalysisResult.parse(pilot_zip, @max_result_bytes)
    assert {:ok, final_document} = AnalysisResult.parse(final_zip, @max_result_bytes)

    verify_pilot(pilot_document, labels)
    verify_final(final_document, labels)
    verify_contracts(pilot_document, final_document)
    write_evidence(evidence, fixture_manifest, [pilot_path, final_path, routes_dir])
  end

  defp analysis_dir do
    candidates = [
      Path.expand("../evaluation/analysis", File.cwd!()),
      Path.expand("evaluation/analysis", File.cwd!())
    ]

    Enum.find(candidates, &File.dir?/1) || hd(candidates)
  end

  defp run_harness(uv, analysis_dir, arguments) do
    script = "tests/rehearsal_harness.py"
    args = ["run", "python", script | arguments]

    {output, status} = System.cmd(uv, args, cd: analysis_dir, stderr_to_stdout: true)

    assert status == 0, "rehearsal harness failed (#{status}):\n#{output}"

    payload =
      output
      |> String.split("\n")
      |> Enum.find_value(fn
        "REHEARSAL_JSON:" <> json -> Jason.decode!(json)
        _line -> nil
      end)

    assert payload, "rehearsal harness produced no JSON payload:\n#{output}"
    payload
  end

  defp tier_entries(paths, labels, phase) do
    Enum.map(labels, fn label ->
      %{tier: label, run_id: rehearsal_uuid(label, phase), archive: File.read!(paths[label])}
    end)
  end

  # Deterministic UUID-shaped run IDs keep repeated rehearsals byte-identical.
  defp rehearsal_uuid(label, phase) do
    hex = Base.encode16(:crypto.hash(:sha256, "#{phase}:#{label}"), case: :lower)

    [
      String.slice(hex, 0, 8),
      String.slice(hex, 8, 4),
      String.slice(hex, 12, 4),
      String.slice(hex, 16, 4),
      String.slice(hex, 20, 12)
    ]
    |> Enum.join("-")
  end

  defp assert_disjoint_schedules(spec, seeds) do
    for key <- ["selection", "evaluation"] do
      declared_pilot = MapSet.new(spec["pilot_seed_schedule"][key])
      declared_final = MapSet.new(spec["final_seed_schedule"][key])
      assert MapSet.size(declared_pilot) > 0
      assert MapSet.size(declared_final) > 0
      assert MapSet.disjoint?(declared_pilot, declared_final), "declared #{key} seeds overlap"
    end

    for key <- ["selection", "attack", "evaluation"] do
      observed_pilot = MapSet.new(seeds["pilot"][key])
      observed_final = MapSet.new(seeds["final"][key])
      assert MapSet.size(observed_pilot) > 0
      assert MapSet.size(observed_final) > 0
      assert MapSet.disjoint?(observed_pilot, observed_final), "observed #{key} seeds overlap"
    end
  end

  defp verify_pilot(document, labels) do
    metadata = document.metadata
    assert metadata["family_scope"] == "study"
    assert metadata["command_mode"] == "study-pilot"
    assert metadata["family_size"] == @family_size
    assert Enum.sort(metadata["tier_labels"]) == Enum.sort(labels)

    rows = document.pilot_results
    ids = Enum.map(rows, & &1["comparison_id"])
    assert length(rows) == @family_size * @candidate_count
    assert length(Enum.uniq(ids)) == @family_size
    assert Enum.all?(rows, &(&1["informative"] == true))

    insufficient = metadata["insufficient_pilot"]
    assert is_boolean(insufficient)
    assert insufficient == false
    assert metadata["recommended_plan_selection_seed_count"] == 5
    assert metadata["recommended_attacks_per_plan"] == 10
  end

  defp verify_final(document, labels) do
    metadata = document.metadata
    assert metadata["family_scope"] == "study"
    assert metadata["command_mode"] == "study-analyze"
    assert metadata["multiplicity_correction"] == "holm"
    assert metadata["uncertainty_sources"] == ["plan_selection", "attack_outcome"]
    assert metadata["family_size"] == @family_size
    assert Enum.sort(metadata["tier_labels"]) == Enum.sort(labels)

    rows = document.primary_results
    ids = Enum.map(rows, & &1["comparison_id"])
    assert length(rows) == @family_size
    assert length(Enum.uniq(ids)) == @family_size
    assert ids == Enum.sort(ids)
    assert MapSet.new(Enum.map(rows, & &1["tier"])) == MapSet.new(labels)

    keys = Enum.map(rows, &{&1["tier"], &1["strategy"], &1["budget"]})
    assert length(Enum.uniq(keys)) == @family_size

    for row <- rows do
      assert row["comparison_id"] == row_comparison_id(row)
      assert row["d_z"] == nil
      assert is_number(row["p_raw"])
      assert is_number(row["p_adjusted"])
      assert(row["p_adjusted"] >= 0.0 and row["p_adjusted"] <= 1.0)
      assert is_boolean(row["informative"])
      assert row["tested_plan_count"] >= 5
      assert row["baseline_plan_count"] >= 5
      assert row["attacks_per_plan"] >= 10
    end

    non_informative = Enum.filter(rows, &(&1["informative"] == false))
    assert [_row] = non_informative

    for row <- non_informative do
      assert row["p_raw"] == 1.0
    end
  end

  defp row_comparison_id(row) do
    Enum.join(
      [
        row["tier"],
        row["model_variant"],
        row["strategy"],
        row["baseline_model_variant"],
        row["baseline"],
        to_string(row["budget"]),
        row["outcome"]
      ],
      "|"
    )
  end

  defp verify_contracts(pilot_document, final_document) do
    for document <- [pilot_document, final_document] do
      changeset =
        EvaluationAnalysisMetadata.changeset(%EvaluationAnalysisMetadata{}, document.metadata)

      assert changeset.valid?, "study metadata contract invalid: #{inspect(changeset.errors)}"
    end

    for row <- final_document.primary_results do
      changeset = EvaluationAnalysisPrimaryRow.changeset(%EvaluationAnalysisPrimaryRow{}, row)
      assert changeset.valid?, "primary row contract invalid: #{inspect(changeset.errors)}"
    end

    for row <- pilot_document.pilot_results do
      changeset = EvaluationAnalysisPilotRow.changeset(%EvaluationAnalysisPilotRow{}, row)
      assert changeset.valid?, "pilot row contract invalid: #{inspect(changeset.errors)}"
    end
  end

  defp write_evidence(evidence, fixture_manifest, paths) do
    fixture_files = [
      Path.join(evidence, "fixtures/study.json"),
      Path.join(evidence, "fixtures/manifest.json"),
      Path.join(evidence, "fixtures/seeds.json")
    ]

    route_files = [
      Path.join([evidence, "routes", "pilot-output.zip"]),
      Path.join([evidence, "routes", "final-output.zip"])
    ]

    tier_files =
      Map.values(fixture_manifest["pilot_tiers"]) ++ Map.values(fixture_manifest["final_tiers"])

    lines =
      (fixture_files ++ paths ++ route_files ++ tier_files)
      |> Enum.filter(&File.regular?/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(fn path ->
        digest = :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
        "#{digest}  #{Path.relative_to(path, evidence)}"
      end)

    File.write!(Path.join(evidence, "checksums.txt"), Enum.join(lines, "\n") <> "\n")
    File.write!(Path.join(evidence, "command_record.txt"), command_record(evidence))

    assert File.regular?(Path.join(evidence, "checksums.txt"))
    assert File.regular?(Path.join(evidence, "command_record.txt"))
  end

  defp command_record(evidence) do
    """
    Crossed-study end-to-end rehearsal.

    Evidence directory: #{evidence}
    Fixture archives: fixtures/pilot/tiers/*.zip, fixtures/final/tiers/*.zip
    Python routes: /v1/study/pilot, /v1/study/analyze
    Bundle builder: NetworkDefense.Evaluation.StudyBundle.archive/2
    Parsers: NetworkDefense.Evaluation.AnalysisResult.parse/2, Phoenix contracts

    Reproduce:
      mix test --include rehearsal test/network_defense/evaluation/end_to_end_rehearsal_test.exs

    This is a synthetic rehearsal. It does not claim Azure measured results.
    """
  end
end
