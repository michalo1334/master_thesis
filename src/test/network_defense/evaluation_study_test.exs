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

  test "rejects missing, incomplete, and warm-up runs", %{manifest_id: id} do
    assert {:error, :not_found} =
             Evaluation.analyze_study([{"small", Ecto.UUID.generate()}], :analyze, spec())

    assert {:ok, run} = Evaluation.start(id)

    assert {:error, :incomplete} =
             Evaluation.analyze_study([{"small", run.id}], :analyze, spec())

    assert {:ok, warmup} = Evaluation.warm_up(id)

    assert {:error, :not_exportable} =
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
      "final_seed_schedule" => %{"selection" => [31], "evaluation" => [41]}
    }
  end
end
