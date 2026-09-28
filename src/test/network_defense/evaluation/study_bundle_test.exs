defmodule NetworkDefense.Evaluation.StudyBundleTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.StudyBundle

  @small "small-archive-bytes"
  @medium "medium-archive-bytes"
  @large "large-archive-bytes"

  @small_run "11111111-1111-4111-8111-111111111111"
  @medium_run "22222222-2222-4222-8222-222222222222"
  @large_run "33333333-3333-4333-8333-333333333333"

  setup do
    previous = Application.get_env(:network_defense, :analysis_service)
    on_exit(fn -> Application.put_env(:network_defense, :analysis_service, previous) end)
    :ok
  end

  test "builds identical bytes for identical inputs" do
    assert {:ok, first} = StudyBundle.archive(tiers(), spec())
    assert {:ok, second} = StudyBundle.archive(tiers(), spec())
    assert first == second
  end

  test "writes members in fixed deterministic order and paths" do
    assert {:ok, bundle} = StudyBundle.archive(tiers(), spec())

    assert member_names(bundle) == [
             "study.json",
             "tiers/large.zip",
             "tiers/medium.zip",
             "tiers/small.zip",
             "checksums.txt"
           ]
  end

  test "checksums cover study.json and each tier archive" do
    assert {:ok, bundle} = StudyBundle.archive(tiers(), spec())
    contents = unzip(bundle)

    lines = contents["checksums.txt"] |> String.split("\n", trim: true)
    assert Enum.count_until(lines, 5) == 4

    for line <- lines do
      [name, digest] = String.split(line, "  ", parts: 2)
      assert digest == sha256(contents[name])
    end
  end

  test "writes tier entries and preserves declared fields" do
    assert {:ok, bundle} = StudyBundle.archive(tiers(), spec())
    contents = unzip(bundle)
    study = Jason.decode!(contents["study.json"])

    assert study["study_id"] == "study-1"
    assert study["specification_version"] == 2
    assert study["multiplicity_correction"] == "holm"
    assert study["expected_family"]["baseline"] == "cvss"
    assert study["pilot"] == spec()["pilot"]
    assert study["pilot_seed_schedule"] == spec()["pilot_seed_schedule"]
    assert study["final_seed_schedule"] == spec()["final_seed_schedule"]

    assert Enum.map(study["tiers"], & &1["label"]) == ["large", "medium", "small"]

    assert Enum.map(study["tiers"], & &1["archive"]) == [
             "tiers/large.zip",
             "tiers/medium.zip",
             "tiers/small.zip"
           ]

    for entry <- study["tiers"] do
      assert String.match?(entry["sha256"], ~r/\A[0-9a-f]{64}\z/)
    end

    assert contents["tiers/small.zip"] == @small
    assert contents["tiers/medium.zip"] == @medium
    assert contents["tiers/large.zip"] == @large
  end

  test "writes canonical JSON with sorted keys and no whitespace" do
    assert {:ok, bundle} = StudyBundle.archive(tiers(), spec())
    raw = unzip(bundle)["study.json"]

    refute String.contains?(raw, ["\n", ": ", ", "])
    assert String.starts_with?(raw, ~s({"expected_family":))
  end

  test "orders nested JSON maps, escapes strings, and preserves list order" do
    special_key = "key\"\\\n"
    special_value = "value\"\\\n\t"

    nested = %{
      "zeta" => true,
      "alpha" => %{"zeta" => "last", special_key => special_value, "alpha" => "first"},
      "list" => [%{"zeta" => "last", "alpha" => "first"}, special_value, special_key]
    }

    assert {:ok, bundle} = StudyBundle.archive(tiers(), spec(%{"nested" => nested}))
    raw = unzip(bundle)["study.json"]
    decoded = Jason.decode!(raw)

    assert decoded["nested"] == nested

    assert raw =~
             ~s("nested":{"alpha":{"alpha":"first",#{Jason.encode!(special_key)}:#{Jason.encode!(special_value)},"zeta":"last"},"list":[{"alpha":"first","zeta":"last"},#{Jason.encode!(special_value)},#{Jason.encode!(special_key)}],"zeta":true})
  end

  test "rejects an invalid study spec" do
    assert {:error, :invalid_study_spec} = StudyBundle.archive(tiers(), %{})
    assert {:error, :invalid_study_spec} = StudyBundle.archive(tiers(), "not-a-map")
    assert {:error, :invalid_study_spec} = StudyBundle.archive(tiers(), %{"study_id" => ""})
  end

  test "rejects duplicate tier labels and run ids" do
    duplicate_label = [
      %{tier: "small", run_id: @small_run, archive: @small},
      %{tier: "small", run_id: @medium_run, archive: @medium}
    ]

    assert {:error, :duplicate_tier_label} = StudyBundle.archive(duplicate_label, spec())

    duplicate_run = [
      %{tier: "small", run_id: @small_run, archive: @small},
      %{tier: "medium", run_id: @small_run, archive: @medium}
    ]

    assert {:error, :duplicate_run_id} = StudyBundle.archive(duplicate_run, spec())
  end

  test "requires UUID run ids even when archive is called directly" do
    assert {:error, :invalid_run_id} =
             StudyBundle.archive([%{tier: "small", run_id: "run-a", archive: @small}], spec())
  end

  test "rejects unsafe tier labels" do
    for label <- ["", "../escape", "a/b", "a\\b", "a..b", ".hidden", "a b"] do
      assert {:error, :unsafe_tier_label} =
               StudyBundle.archive([%{tier: label, run_id: @small_run, archive: @small}], spec())
    end
  end

  test "rejects malformed tier entries" do
    assert {:error, :invalid_tier} = StudyBundle.archive(["small"], spec())
    assert {:error, :invalid_tier} = StudyBundle.archive([%{tier: "small"}], spec())
  end

  test "rejects a tier archive larger than the configured limit" do
    Application.put_env(:network_defense, :analysis_service, max_zip_bytes: 4)

    assert {:error, :tier_archive_too_large} =
             StudyBundle.archive([%{tier: "small", run_id: @small_run, archive: @small}], spec())
  end

  test "rejects input larger than the configured limit" do
    Application.put_env(:network_defense, :analysis_service, max_zip_bytes: 21)

    tiers = [
      %{tier: "small", run_id: @small_run, archive: @small},
      %{tier: "medium", run_id: @medium_run, archive: @medium}
    ]

    assert {:error, :input_too_large} = StudyBundle.archive(tiers, spec())
  end

  test "rejects a bundle larger than the configured output limit" do
    Application.put_env(:network_defense, :analysis_service, max_zip_bytes: byte_size(@small))

    assert {:error, :output_too_large} =
             StudyBundle.archive([%{tier: "small", run_id: @small_run, archive: @small}], spec())
  end

  test "rejects duplicate declared tier labels" do
    declared = spec(%{"tiers" => ["small", "small", "medium", "large"]})
    assert {:error, :invalid_study_spec} = StudyBundle.archive(tiers(), declared)
  end

  test "rejects tier labels that disagree with the declared spec" do
    declared = spec(%{"tiers" => ["small", "medium"]})
    assert {:error, :tier_declaration_mismatch} = StudyBundle.archive(tiers(), declared)
  end

  test "accepts declared tier labels that match" do
    declared = spec(%{"tiers" => [%{"label" => "large"}, "medium", "small"]})
    assert {:ok, _bundle} = StudyBundle.archive(tiers(), declared)
  end

  defp tiers do
    [
      %{tier: "medium", run_id: @medium_run, archive: @medium},
      %{tier: "small", run_id: @small_run, archive: @small},
      %{tier: "large", run_id: @large_run, archive: @large}
    ]
  end

  defp spec(overrides \\ %{}) do
    Map.merge(
      %{
        "study_id" => "study-1",
        "specification_version" => 2,
        "expected_family" => %{
          "strategies" => ["alt-a"],
          "baseline" => "cvss",
          "budgets" => [1],
          "outcome" => "mission_impact"
        },
        "pilot" => %{
          "ci_half_width" => 1.0,
          "plan_count_candidates" => [5],
          "attacks_per_plan_candidates" => [10]
        },
        "multiplicity_correction" => "holm",
        "pilot_seed_schedule" => %{"selection" => [11], "evaluation" => [21]},
        "final_seed_schedule" => %{"selection" => [31], "evaluation" => [41]}
      },
      overrides
    )
  end

  defp member_names(bundle) do
    {:ok, entries} = :zip.list_dir(bundle)

    for {:zip_file, name, _info, _comment, _offset, _comp_size} <- entries,
        do: to_string(name)
  end

  defp unzip(bundle) do
    {:ok, entries} = :zip.extract(bundle, [:memory])
    Map.new(entries, fn {name, content} -> {to_string(name), content} end)
  end

  defp sha256(content),
    do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
