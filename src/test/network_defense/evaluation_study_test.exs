defmodule NetworkDefense.Evaluation.StudyTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.AnalysisClient
  alias NetworkDefense.EvaluationFixtures

  setup do
    id = "study-manifest-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(id, EvaluationFixtures.analysis_manifest())

    %{manifest_id: id}
  end

  test "exports completed tiers and submits one study bundle", %{manifest_id: id} do
    assert {:ok, run} = Evaluation.start(id)
    assert {:ok, completed} = Evaluation.run(run.id)

    :meck.new(AnalysisClient, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    :meck.expect(AnalysisClient, :analyze_study, fn bundle, study_id, mode ->
      assert is_binary(bundle)
      assert study_id == "study-1"
      assert mode == :analyze

      assert {:ok, entries} = :zip.list_dir(bundle)

      names =
        for {:zip_file, name, _info, _comment, _offset, _comp_size} <- entries,
            do: to_string(name)

      assert names == ["study.json", "tiers/small.zip", "checksums.txt"]

      {:ok, "study-analysis-zip"}
    end)

    assert {:ok, "study-analysis-zip"} =
             Evaluation.analyze_study([{"small", completed.id}], :analyze, spec())
  end

  test "accepts map-form tiers and builds the same bundle as the tuple form", %{
    manifest_id: id
  } do
    assert {:ok, run} = Evaluation.start(id)
    assert {:ok, completed} = Evaluation.run(run.id)

    mock_collecting_analysis_client()

    assert {:ok, "study-analysis-zip"} =
             Evaluation.analyze_study([{"small", completed.id}], :analyze, spec())

    assert_received {:study_bundle, tuple_bundle}

    assert {:ok, "study-analysis-zip"} =
             Evaluation.analyze_study(
               [%{tier: "small", run_id: completed.id}],
               :analyze,
               spec()
             )

    assert_received {:study_bundle, map_bundle}
    assert map_bundle == tuple_bundle
  end

  test "returns controlled errors for map-form tiers", %{manifest_id: id} do
    assert {:ok, run} = Evaluation.start(id)

    assert {:error, :not_found} =
             Evaluation.analyze_study(
               [%{tier: "small", run_id: Ecto.UUID.generate()}],
               :analyze,
               spec()
             )

    assert {:error, :incomplete} =
             Evaluation.analyze_study([%{tier: "small", run_id: run.id}], :analyze, spec())

    assert {:error, :duplicate_tier_label} =
             Evaluation.analyze_study(
               [
                 %{tier: "small", run_id: Ecto.UUID.generate()},
                 %{tier: "small", run_id: Ecto.UUID.generate()}
               ],
               :analyze,
               spec()
             )

    assert {:error, :invalid_run_id} =
             Evaluation.analyze_study(
               [%{tier: "small", run_id: "not-a-uuid"}],
               :analyze,
               spec()
             )
  end

  test "rejects missing, incomplete, and warm-up runs", %{manifest_id: id} do
    assert {:error, :not_found} =
             Evaluation.analyze_study([{"small", Ecto.UUID.generate()}], :analyze, spec())

    assert {:ok, run} = Evaluation.start(id)

    assert {:error, :incomplete} =
             Evaluation.analyze_study([{"small", run.id}], :analyze, spec())

    assert {:ok, warmup} = Evaluation.warm_up(id)

    assert {:error, :warmup_run} =
             Evaluation.analyze_study([{"small", warmup.id}], :analyze, spec())
  end

  test "rejects duplicate tier labels, duplicate run ids, and invalid run ids" do
    first = Ecto.UUID.generate()
    second = Ecto.UUID.generate()

    assert {:error, :duplicate_tier_label} =
             Evaluation.analyze_study([{"small", first}, {"small", second}], :analyze, spec())

    assert {:error, :duplicate_run_id} =
             Evaluation.analyze_study([{"small", first}, {"medium", first}], :analyze, spec())

    assert {:error, :invalid_run_id} =
             Evaluation.analyze_study([{"small", "not-a-uuid"}], :analyze, spec())

    assert {:error, :no_tiers} = Evaluation.analyze_study([], :analyze, spec())
  end

  describe "study specification validation" do
    setup %{manifest_id: id} do
      assert {:ok, run} = Evaluation.start(id)
      assert {:ok, completed} = Evaluation.run(run.id)
      %{completed: completed}
    end

    test "rejects a malformed finite value before bundle construction", %{completed: completed} do
      mock_unused_analysis_client()

      assert {:error, :invalid_study_spec} =
               Evaluation.analyze_study(
                 [{"small", completed.id}],
                 :analyze,
                 put_in(spec(), ["pilot", "ci_half_width"], "1e400")
               )
    end

    test "derives tier declarations from the tier arguments when the specification omits tiers",
         %{completed: completed} do
      refute Map.has_key?(spec(), "tiers")

      :meck.new(AnalysisClient, [:passthrough])
      on_exit(fn -> :meck.unload() end)

      :meck.expect(AnalysisClient, :analyze_study, fn bundle, study_id, mode ->
        assert study_id == "study-1"
        assert mode == :analyze
        assert Enum.map(study_tiers(bundle), & &1["label"]) == ["small"]
        {:ok, "study-analysis-zip"}
      end)

      assert {:ok, "study-analysis-zip"} =
               Evaluation.analyze_study([{"small", completed.id}], :analyze, spec())
    end

    test "rejects a declared tier list that conflicts with the tier arguments",
         %{completed: completed} do
      declared = Map.put(spec(), "tiers", ["small", "medium"])

      assert {:error, :tier_declaration_mismatch} =
               Evaluation.analyze_study([{"small", completed.id}], :analyze, declared)
    end

    test "rejects an invalid declared tier list before bundle construction",
         %{completed: completed} do
      mock_unused_analysis_client()

      for tiers <- [[], "small", ["small", "small"]] do
        assert {:error, :invalid_study_spec} =
                 Evaluation.analyze_study(
                   [{"small", completed.id}],
                   :analyze,
                   Map.put(spec(), "tiers", tiers)
                 )
      end
    end
  end

  defp mock_collecting_analysis_client do
    :meck.new(AnalysisClient, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    :meck.expect(AnalysisClient, :analyze_study, fn bundle, _study_id, _mode ->
      send(self(), {:study_bundle, bundle})
      {:ok, "study-analysis-zip"}
    end)
  end

  defp mock_unused_analysis_client do
    :meck.new(AnalysisClient, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    :meck.expect(AnalysisClient, :analyze_study, fn _bundle, _study_id, _mode ->
      flunk("analysis service must not run for an invalid specification")
    end)
  end

  defp study_tiers(bundle) do
    {:ok, entries} = :zip.extract(bundle, [:memory])

    entries
    |> Map.new(fn {name, content} -> {to_string(name), content} end)
    |> Map.fetch!("study.json")
    |> Jason.decode!()
    |> Map.fetch!("tiers")
  end

  defp spec do
    %{
      "study_id" => "study-1",
      "specification_version" => 1,
      "expected_family" => %{
        "strategies" => ["simulation_informed"],
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
      "final_seed_schedule" => %{"selection" => [101, 201], "evaluation" => [9001]}
    }
  end
end
