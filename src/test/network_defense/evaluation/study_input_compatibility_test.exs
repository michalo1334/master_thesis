defmodule NetworkDefense.Evaluation.StudyInputCompatibilityTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Evaluation.StudyInputCompatibility
  alias NetworkDefense.EvaluationFixtures

  describe "shape/1 and summary/1" do
    test "derives the expected comparison matrix and both seed schedules" do
      assert {:ok, shape} =
               StudyInputCompatibility.shape(EvaluationFixtures.study_specification())

      assert shape.baseline == "cvss"
      assert shape.outcome == "mission_impact"
      assert MapSet.new([{"simulation_informed", 1, "cvss", "mission_impact"}]) == shape.pairs

      assert shape.schedules.pilot.selection == MapSet.new([101, 201])
      assert shape.schedules.pilot.evaluation == MapSet.new([9001])
      assert shape.schedules.final.selection == MapSet.new([301, 401])
      assert shape.schedules.final.evaluation == MapSet.new([9002])

      assert StudyInputCompatibility.family(shape) ==
               EvaluationFixtures.study_expected_family()

      assert StudyInputCompatibility.summary(shape) =~
               "strategies: simulation_informed"
    end

    test "rejects a specification without a declared family or schedule" do
      assert {:error, :invalid_study_spec} =
               StudyInputCompatibility.shape(%{"study_id" => "s"})

      specification =
        EvaluationFixtures.study_specification()
        |> Map.delete("final_seed_schedule")

      assert {:error, :invalid_study_spec} = StudyInputCompatibility.shape(specification)
    end
  end

  describe "compatible?/2" do
    setup do
      assert {:ok, shape} =
               StudyInputCompatibility.shape(EvaluationFixtures.study_specification())

      %{shape: shape}
    end

    test "accepts a run whose matrix matches the family", %{shape: shape} do
      run = run(EvaluationFixtures.analysis_manifest())

      assert StudyInputCompatibility.compatible?(run, shape)
    end

    test "rejects a run whose matrix does not match the family", %{shape: shape} do
      run = run(EvaluationFixtures.valid_manifest())

      refute StudyInputCompatibility.compatible?(run, shape)
    end

    test "rejects a run with two declared model variants", %{shape: shape} do
      manifest =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["model_variants"], [
          %{"id" => "full", "objective" => "mission_then_blast_radius"},
          %{"id" => "mission_only", "objective" => "mission_impact_only"}
        ])

      refute StudyInputCompatibility.compatible?(run(manifest), shape)
    end

    test "rejects a run without the holm correction", %{shape: shape} do
      manifest =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["analysis", "multiplicity_correction"], "none")

      refute StudyInputCompatibility.compatible?(run(manifest), shape)
    end

    test "rejects a run with an invalid common setting", %{shape: shape} do
      manifest =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["analysis", "bootstrap_resamples"], 0)

      refute StudyInputCompatibility.compatible?(run(manifest), shape)
    end

    test "rejects a run with a duplicate primary comparison", %{shape: shape} do
      [comparison] =
        get_in(EvaluationFixtures.analysis_manifest(), ["analysis", "primary_comparisons"])

      manifest =
        put_in(EvaluationFixtures.analysis_manifest(), ["analysis", "primary_comparisons"], [
          comparison,
          comparison
        ])

      refute StudyInputCompatibility.compatible?(run(manifest), shape)
    end

    test "rejects a nil run", %{shape: shape} do
      refute StudyInputCompatibility.compatible?(nil, shape)
    end
  end

  describe "mode_compatible?/3" do
    setup do
      assert {:ok, shape} =
               StudyInputCompatibility.shape(EvaluationFixtures.study_specification())

      %{shape: shape}
    end

    test "accepts a pilot run in pilot mode and rejects it in final mode", %{shape: shape} do
      run = run(EvaluationFixtures.analysis_manifest())

      assert StudyInputCompatibility.mode_compatible?(run, shape, :pilot)
      refute StudyInputCompatibility.mode_compatible?(run, shape, :final)
    end

    test "accepts a final run in final mode and rejects it in pilot mode", %{shape: shape} do
      run = run(EvaluationFixtures.final_manifest())

      assert StudyInputCompatibility.mode_compatible?(run, shape, :final)
      refute StudyInputCompatibility.mode_compatible?(run, shape, :pilot)
    end

    test "rejects a run whose evaluation seed is outside the mode schedule", %{shape: shape} do
      manifest =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["evaluation", "seed"], 999_999)

      refute StudyInputCompatibility.mode_compatible?(run(manifest), shape, :pilot)
    end

    test "rejects a run whose selection seed is outside the mode schedule", %{shape: shape} do
      manifest =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["strategy_runs"], [
          %{
            "model_variant" => "full",
            "strategy" => "cvss",
            "budget" => 1,
            "selection_seeds" => [999_999]
          },
          %{
            "model_variant" => "full",
            "strategy" => "simulation_informed",
            "budget" => 1,
            "selection_seeds" => [201]
          }
        ])

      refute StudyInputCompatibility.mode_compatible?(run(manifest), shape, :pilot)
    end

    test "accepts a declared selection superset for one strategy run", %{shape: shape} do
      manifest =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["strategy_runs"], [
          %{
            "model_variant" => "full",
            "strategy" => "cvss",
            "budget" => 1,
            "selection_seeds" => [101, 201]
          },
          %{
            "model_variant" => "full",
            "strategy" => "simulation_informed",
            "budget" => 1,
            "selection_seeds" => [101]
          }
        ])

      assert StudyInputCompatibility.mode_compatible?(run(manifest), shape, :pilot)
      refute StudyInputCompatibility.mode_compatible?(run(manifest), shape, :final)
    end

    test "rejects a run without a declared evaluation seed", %{shape: shape} do
      manifest =
        EvaluationFixtures.analysis_manifest()
        |> Map.update!("evaluation", &Map.delete(&1, "seed"))

      refute StudyInputCompatibility.mode_compatible?(run(manifest), shape, :pilot)
    end
  end

  describe "consistent?/3" do
    setup do
      assert {:ok, shape} =
               StudyInputCompatibility.shape(EvaluationFixtures.study_specification())

      %{shape: shape}
    end

    test "accepts runs that share the variant, settings, and declared evaluation set", %{
      shape: shape
    } do
      assert StudyInputCompatibility.consistent?(
               [
                 run(EvaluationFixtures.analysis_manifest()),
                 run(EvaluationFixtures.analysis_manifest())
               ],
               shape,
               :pilot
             )
    end

    test "rejects runs with different model variants", %{shape: shape} do
      other =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["model_variants"], [%{"id" => "mission_only"}])

      refute StudyInputCompatibility.consistent?(
               [
                 run(EvaluationFixtures.analysis_manifest()),
                 run(other)
               ],
               shape,
               :pilot
             )
    end

    test "rejects runs with different common settings", %{shape: shape} do
      other =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["analysis", "bootstrap_resamples"], 250)

      refute StudyInputCompatibility.consistent?(
               [
                 run(EvaluationFixtures.analysis_manifest()),
                 run(other)
               ],
               shape,
               :pilot
             )
    end

    test "rejects a mapping that does not cover every declared evaluation seed", %{shape: _shape} do
      specification =
        EvaluationFixtures.study_specification()
        |> put_in(["pilot_seed_schedule", "evaluation"], [9001, 9003])

      assert {:ok, wide} = StudyInputCompatibility.shape(specification)
      run = run(EvaluationFixtures.analysis_manifest())

      assert StudyInputCompatibility.mode_compatible?(run, wide, :pilot)
      refute StudyInputCompatibility.consistent?([run, run], wide, :pilot)
    end

    test "rejects a mapping that brings an undeclared evaluation seed", %{shape: shape} do
      other =
        EvaluationFixtures.analysis_manifest()
        |> put_in(["evaluation", "seed"], 999_999)

      refute StudyInputCompatibility.consistent?([run(other)], shape, :pilot)
    end

    test "rejects an empty mapping", %{shape: shape} do
      refute StudyInputCompatibility.consistent?([], shape, :pilot)
    end

    test "rejects a final mapping built from pilot runs", %{shape: shape} do
      runs = [run(EvaluationFixtures.analysis_manifest())]

      refute StudyInputCompatibility.consistent?(runs, shape, :final)
    end
  end

  defp run(manifest), do: %EvaluationRun{resolved_manifest: manifest}
end
