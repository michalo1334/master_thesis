defmodule NetworkDefense.Evaluation.StudyRunnerTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.AnalysisClient
  alias NetworkDefense.Evaluation.AnalysisLimits
  import Ecto.Query

  alias NetworkDefense.Evaluation.OutputContract
  alias NetworkDefense.Evaluation.StudyRunner
  alias NetworkDefense.EvaluationFixtures
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Repo

  setup do
    manifest_id = "study-runner-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.analysis_manifest())

    %{manifest_id: manifest_id}
  end

  describe "tier run listing" do
    test "lists only exportable completed non-warm-up runs for a declared tier", %{
      manifest_id: id
    } do
      completed = EvaluationFixtures.completed_run(id)
      running = EvaluationFixtures.running_run(id)
      warmup = EvaluationFixtures.completed_run(id, "warmup")

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:ok, runs} = StudyRunner.list_tier_runs(saved.id, "small", :pilot)
      ids = Enum.map(runs, & &1.id)

      assert completed.id in ids
      refute running.id in ids
      refute warmup.id in ids

      summary = Enum.find(runs, &(&1.id == completed.id))
      assert summary.manifest_id == id
      assert summary.manifest_title == "T"
      assert is_binary(summary.graph_title)
      assert is_binary(summary.completed_at)
      assert summary.plan_count == 2
      assert summary.trial_count == 6
    end

    test "seeds one completed tier run and keeps warm-up and running runs out" do
      scenario = EvaluationFixtures.seed_study_scenario(["small"])
      completed = hd(scenario.runs)

      assert {:ok, runs} = StudyRunner.list_tier_runs(scenario.specification.id, "small", :pilot)
      ids = Enum.map(runs, & &1.id)

      assert completed.id in ids
      refute scenario.warmup_run.id in ids
      refute scenario.running_run.id in ids
    end

    test "rejects an undeclared tier and a missing specification", %{manifest_id: id} do
      _run = EvaluationFixtures.completed_run(id)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:error, :tier_declaration_mismatch} =
               StudyRunner.list_tier_runs(saved.id, "large", :pilot)

      assert {:error, :specification_not_found} =
               StudyRunner.list_tier_runs(Ecto.UUID.generate(), "small", :pilot)
    end

    test "rejects persisted plan seeds outside the selected schedule", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      plan =
        OptimizationRun
        |> where([plan], plan.evaluation_run_id == ^run.id)
        |> limit(1)
        |> Repo.one!()

      {:ok, _plan} = plan |> Ecto.Changeset.change(selection_seed: 999_999) |> Repo.update()

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:ok, []} = StudyRunner.list_tier_runs(saved.id, "small", :pilot)

      assert {:error, :incompatible_run} =
               StudyRunner.preflight(saved.id, [{"small", run.id}], :pilot)
    end

    test "excludes a completed run without a valid runtime", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      {:ok, run} = run |> Ecto.Changeset.change(runtime_ms: nil) |> Repo.update()

      assert {:ok, []} = StudyRunner.list_tier_runs(saved.id, "small", :pilot)

      assert {:error, :missing_runtime} =
               StudyRunner.preflight(saved.id, [{"small", run.id}], :pilot)

      assert StudyRunner.wire_error(:missing_runtime) == :run_not_exportable
    end

    test "rejects a completed warm-up run with a dedicated error even when it is otherwise exportable",
         %{manifest_id: id} do
      warmup = EvaluationFixtures.completed_run(id, "warmup")

      assert warmup.status == "completed"
      assert is_integer(warmup.runtime_ms)
      refute OutputContract.exportable?(warmup)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:ok, runs} = StudyRunner.list_tier_runs(saved.id, "small", :pilot)
      refute Enum.any?(runs, &(&1.id == warmup.id))

      assert {:error, :warmup_run} =
               StudyRunner.preflight(saved.id, [{"small", warmup.id}], :pilot)

      assert StudyRunner.wire_error(:warmup_run) == :run_warmup
    end

    test "filters runs whose comparison matrix does not match the specification",
         %{manifest_id: id} do
      compatible = EvaluationFixtures.completed_run(id)
      incompatible = incompatible_run()

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:ok, runs} = StudyRunner.list_tier_runs(saved.id, "small", :pilot)
      ids = Enum.map(runs, & &1.id)

      assert compatible.id in ids
      refute incompatible.id in ids

      assert {:ok, required} = StudyRunner.required_inputs(saved.id)
      assert required =~ "strategies: simulation_informed"
    end

    test "filters a run whose matrix is compatible but whose model variant is not single",
         %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      assert {:ok, _run} =
               run
               |> Ecto.Changeset.change(
                 resolved_manifest:
                   put_in(
                     run.resolved_manifest,
                     ["model_variants"],
                     [%{"id" => "full"}, %{"id" => "mission_only"}]
                   )
               )
               |> Repo.update()

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:ok, runs} = StudyRunner.list_tier_runs(saved.id, "small", :pilot)
      refute Enum.any?(runs, &(&1.id == run.id))
    end
  end

  describe "prepare/3" do
    test "rejects a mapping with an incompatible run" do
      incompatible = incompatible_run()

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      expect_unused_analysis()

      assert {:error, :incompatible_run} =
               StudyRunner.preflight(saved.id, [{"small", incompatible.id}], :pilot)

      assert StudyRunner.wire_error(:incompatible_run) == :run_incompatible
    end

    test "rejects a mapping whose tiers disagree on common settings" do
      assert {:ok, settings_a} = EvaluationFixtures.save_manifest("settings-a", manifest())

      assert {:ok, settings_b} =
               EvaluationFixtures.save_manifest(
                 "settings-b",
                 put_in(manifest(), ["analysis", "bootstrap_resamples"], 250)
               )

      run_a = EvaluationFixtures.completed_run(settings_a.manifest_id)
      run_b = EvaluationFixtures.completed_run(settings_b.manifest_id)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(two_tier_specification())

      expect_unused_analysis()

      assert {:error, :incompatible_run} =
               StudyRunner.preflight(
                 saved.id,
                 [
                   {"small", run_a.id},
                   {"medium", run_b.id}
                 ],
                 :pilot
               )
    end

    test "builds the same bundle as execution without calling the service", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)
      spec = single_tier_specification()
      test_pid = self()

      expect_analysis(fn bundle, _study_id, :pilot ->
        send(test_pid, {:submitted_bundle, bundle})
        {:ok, "analysis-result"}
      end)

      assert {:ok, prepared} = StudyRunner.prepare([{"small", run.id}], spec, :pilot)
      assert {:ok, "analysis-result"} = StudyRunner.analyze([{"small", run.id}], spec, :pilot)
      assert_receive {:submitted_bundle, submitted}
      assert submitted == prepared.bundle
    end

    test "preflight resolves the saved version and never submits", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      expect_unused_analysis()

      assert {:ok, preflight} = StudyRunner.preflight(saved.id, [{"small", run.id}], :pilot)
      assert preflight.study_id == "topology-scale-study"
      assert preflight.tier_labels == ["small"]
      assert preflight.bundle_bytes > 0
    end

    test "preflight rejects a missing declared tier and an unknown run", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(
                 EvaluationFixtures.study_specification()
               )

      assert {:error, :tier_declaration_mismatch} =
               StudyRunner.preflight(saved.id, [{"small", run.id}], :pilot)

      assert {:error, :not_found} =
               StudyRunner.preflight(
                 saved.id,
                 [
                   {"small", Ecto.UUID.generate()},
                   {"medium", Ecto.UUID.generate()},
                   {"large", Ecto.UUID.generate()}
                 ],
                 :pilot
               )
    end

    test "preflight rejects duplicate tier labels and duplicate run ids", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:error, :duplicate_run_id} =
               StudyRunner.preflight(
                 saved.id,
                 [
                   {"small", run.id},
                   {"medium", run.id}
                 ],
                 :pilot
               )

      assert {:error, :duplicate_tier_label} =
               StudyRunner.preflight(
                 saved.id,
                 [
                   {"small", run.id},
                   {"small", Ecto.UUID.generate()}
                 ],
                 :pilot
               )

      assert {:error, :specification_not_found} =
               StudyRunner.preflight(Ecto.UUID.generate(), [{"small", run.id}], :pilot)
    end
  end

  describe "execute/4" do
    test "emits the named phases in order and parses the result", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)
      test_pid = self()

      expect_analysis(fn bundle, _study_id, :pilot ->
        {:ok, EvaluationFixtures.study_result_archive_for_bundle("pilot", bundle)}
      end)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      on_phase = fn phase -> send(test_pid, {:phase, phase}) end

      assert {:ok, %{archive: archive, analysis: analysis}} =
               StudyRunner.execute(saved.id, [{"small", run.id}], :pilot, on_phase)

      assert is_binary(archive)

      assert drain_phases() == [
               :building_bundle,
               :submitting_analysis,
               :waiting_for_service,
               :validating_result,
               :complete
             ]

      assert StudyRunner.pilot_eligible?(:pilot, analysis)
    end

    test "maps an analysis failure to a domain error for a final run" do
      run = final_run()

      expect_analysis(fn _bundle, _study_id, :analyze -> {:error, :transport} end)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:error, :transport} =
               StudyRunner.execute(saved.id, [{"small", run.id}], :final, fn _phase -> :ok end)
    end

    test "accepts a separate final mapping in final mode", %{manifest_id: id} do
      pilot_run = EvaluationFixtures.completed_run(id)
      final_run = final_run()

      expect_analysis(fn bundle, _study_id, :analyze ->
        {:ok, EvaluationFixtures.study_result_archive_for_bundle("analyze", bundle)}
      end)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:error, :incompatible_run} =
               StudyRunner.preflight(saved.id, [{"small", pilot_run.id}], :final)

      assert {:ok, %{archive: archive, analysis: analysis}} =
               StudyRunner.execute(saved.id, [{"small", final_run.id}], :final, fn _phase ->
                 :ok
               end)

      assert is_binary(archive)

      assert analysis.metadata["command_mode"] == "study-analyze"
    end

    test "lists disjoint pilot and final runs per mode", %{manifest_id: id} do
      pilot_run = EvaluationFixtures.completed_run(id)
      final_run = final_run()

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:ok, pilot_runs} = StudyRunner.list_tier_runs(saved.id, "small", :pilot)
      pilot_ids = Enum.map(pilot_runs, & &1.id)
      assert pilot_run.id in pilot_ids
      refute final_run.id in pilot_ids

      assert {:ok, final_runs} = StudyRunner.list_tier_runs(saved.id, "small", :final)
      final_ids = Enum.map(final_runs, & &1.id)
      assert final_run.id in final_ids
      refute pilot_run.id in final_ids
    end

    test "maps a malformed result archive to invalid_result", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      expect_analysis(fn _bundle, _study_id, :pilot -> {:ok, "not a ZIP"} end)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      assert {:error, :invalid_zip} =
               StudyRunner.execute(saved.id, [{"small", run.id}], :pilot, fn _phase -> :ok end)

      assert StudyRunner.wire_error(:invalid_zip) == :invalid_result
    end
  end

  describe "result binding" do
    test "rejects every mismatched service result before storing eligibility", %{manifest_id: id} do
      run = EvaluationFixtures.completed_run(id)

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      mismatches = [
        {:mode, "analyze", %{}},
        {:study_id, "pilot", %{"study_id" => "other-study"}},
        {:specification_version, "pilot", %{"specification_version" => 2}},
        {:family_scope, "pilot", %{"family_scope" => "evaluation"}},
        {:family_size, "pilot", %{"family_size" => 2}},
        {:multiplicity_correction, "pilot", %{"multiplicity_correction" => "bonferroni"}},
        {:expected_family, "pilot",
         %{
           "expected_family" => %{
             "strategies" => ["random"],
             "baseline" => "cvss",
             "budgets" => [1],
             "outcome" => "mission_impact"
           }
         }},
        {:tier_labels, "pilot", %{"tier_labels" => ["large"]}},
        {:mismatched_digest, "pilot",
         %{
           "tier_context" => [
             %{
               "label" => "small",
               "archive" => "tiers/small.zip",
               "archive_sha256" => String.duplicate("b", 64)
             }
           ]
         }},
        {:missing_context, "pilot", %{"tier_context" => nil}},
        {:duplicate_context, "pilot",
         %{
           "tier_context" => [
             %{
               "label" => "small",
               "archive" => "tiers/small.zip",
               "archive_sha256" => String.duplicate("a", 64)
             },
             %{
               "label" => "small",
               "archive" => "tiers/other.zip",
               "archive_sha256" => String.duplicate("a", 64)
             }
           ]
         }}
      ]

      :meck.new(AnalysisClient, [:passthrough])

      on_exit(fn ->
        :meck.unload()
        :persistent_term.erase({__MODULE__, :study_result_options})
      end)

      :meck.expect(AnalysisClient, :analyze_study, fn bundle, _study_id, :pilot ->
        {mode, metadata_overrides, rows_overrides} =
          :persistent_term.get({__MODULE__, :study_result_options}, {"pilot", %{}, %{}})

        {:ok,
         EvaluationFixtures.study_result_archive_for_bundle(
           mode,
           bundle,
           metadata_overrides,
           rows_overrides
         )}
      end)

      Enum.each(mismatches, fn {label, mode, overrides} ->
        :persistent_term.put({__MODULE__, :study_result_options}, {mode, overrides, %{}})

        assert {:error, reason} =
                 StudyRunner.execute(saved.id, [{"small", run.id}], :pilot, fn _phase -> :ok end),
               "expected #{label} mismatch to fail"

        assert StudyRunner.wire_error(reason) == :invalid_result
      end)

      row_mismatches = [
        {:missing, %{"pilot_results.json" => []}},
        {:duplicate,
         %{
           "pilot_results.json" => [
             EvaluationFixtures.pilot_result_row(),
             EvaluationFixtures.pilot_result_row()
           ]
         }},
        {:extra,
         %{
           "pilot_results.json" => [
             EvaluationFixtures.pilot_result_row(),
             %{EvaluationFixtures.pilot_result_row() | "comparison_id" => "unexpected"}
           ]
         }}
      ]

      Enum.each(row_mismatches, fn {label, rows} ->
        :persistent_term.put({__MODULE__, :study_result_options}, {"pilot", %{}, rows})

        assert {:error, reason} =
                 StudyRunner.execute(saved.id, [{"small", run.id}], :pilot, fn _phase -> :ok end),
               "expected #{label} pilot rows to fail"

        assert StudyRunner.wire_error(reason) == :invalid_result
      end)

      :persistent_term.put({__MODULE__, :study_result_options}, {"pilot", %{}, %{}})

      assert {:ok, %{analysis: analysis}} =
               StudyRunner.execute(saved.id, [{"small", run.id}], :pilot, fn _phase -> :ok end)

      assert StudyRunner.pilot_eligible?(:pilot, analysis)
      assert StudyRunner.wire_error(:invalid_result) == :invalid_result
    end
  end

  describe "final result binding" do
    test "rejects missing, duplicate, and extra primary comparison identities" do
      run = final_run()

      assert {:ok, saved} =
               EvaluationFixtures.save_study_specification(single_tier_specification())

      row_mismatches = [
        {:missing, %{"primary_results.json" => []}},
        {:duplicate,
         %{
           "primary_results.json" => [
             EvaluationFixtures.primary_result_row(),
             EvaluationFixtures.primary_result_row()
           ]
         }},
        {:extra,
         %{
           "primary_results.json" => [
             EvaluationFixtures.primary_result_row(),
             %{EvaluationFixtures.primary_result_row() | "comparison_id" => "unexpected"}
           ]
         }}
      ]

      Enum.each(row_mismatches, fn {label, rows} ->
        expect_analysis(fn bundle, _study_id, :analyze ->
          {:ok, EvaluationFixtures.study_result_archive_for_bundle("analyze", bundle, %{}, rows)}
        end)

        assert {:error, reason} =
                 StudyRunner.execute(saved.id, [{"small", run.id}], :final, fn _phase -> :ok end),
               "expected #{label} primary rows to fail"

        assert StudyRunner.wire_error(reason) == :invalid_result
        :meck.unload()
      end)
    end
  end

  describe "pilot eligibility" do
    test "accepts a positive recommendation without stop conditions" do
      assert StudyRunner.pilot_eligibility(pilot_analysis(%{})) == :eligible
    end

    test "rejects an insufficient pilot" do
      analysis =
        pilot_analysis(%{
          "insufficient_pilot" => true,
          "recommendation" => %{
            "plan_selection_seed_count" => nil,
            "attacks_per_plan" => nil,
            "insufficient_pilot" => true,
            "non_informative_comparisons" => []
          }
        })

      assert StudyRunner.pilot_eligibility(analysis) == {:ineligible, :insufficient_pilot}
    end

    test "rejects a non-informative comparison" do
      analysis = pilot_analysis(%{"non_informative_comparisons" => ["c1"]})

      assert StudyRunner.pilot_eligibility(analysis) ==
               {:ineligible, :non_informative_comparison}
    end

    test "rejects a recommendation without both sample counts" do
      analysis =
        pilot_analysis(%{
          "recommendation" => %{
            "plan_selection_seed_count" => nil,
            "attacks_per_plan" => nil,
            "insufficient_pilot" => false,
            "non_informative_comparisons" => []
          }
        })

      assert StudyRunner.pilot_eligibility(analysis) == {:ineligible, :invalid_recommendation}
    end

    test "rejects a non-pilot result" do
      analysis = pilot_analysis(%{"command_mode" => "study-analyze"})

      assert StudyRunner.pilot_eligibility(analysis) == {:ineligible, :invalid_pilot_result}
      assert StudyRunner.pilot_eligible?(:final, analysis) == nil
    end
  end

  describe "browser delivery limits" do
    test "keeps the browser limit below the service maximum" do
      assert AnalysisLimits.browser_result_bytes() < AnalysisLimits.max_zip_bytes()
    end

    test "accepts a result at the limit and rejects one byte more" do
      limit = AnalysisLimits.browser_result_bytes()

      assert AnalysisLimits.browser_deliverable?(:binary.copy(<<0>>, limit))
      refute AnalysisLimits.browser_deliverable?(:binary.copy(<<0>>, limit + 1))
      refute AnalysisLimits.browser_deliverable?(:not_a_binary)
    end
  end

  describe "wire error mapping" do
    test "maps each domain error to one stable wire code" do
      assert StudyRunner.wire_error(:duplicate_run_id) == :duplicate_run_id
      assert StudyRunner.wire_error(:result_too_large) == :result_too_large
      assert StudyRunner.wire_error(:unsafe_tier_label) == :unsafe_tier_label
      assert StudyRunner.wire_error(:not_found) == :run_not_found
      assert StudyRunner.wire_error(:incomplete) == :run_incomplete
      assert StudyRunner.wire_error(:not_exportable) == :run_not_exportable
      assert StudyRunner.wire_error(:invalid_study_spec) == :invalid_specification
      assert StudyRunner.wire_error(:invalid_study_tiers) == :invalid_tier_selection
      assert StudyRunner.wire_error(:tier_declaration_mismatch) == :tier_declaration_mismatch
      assert StudyRunner.wire_error(:warmup_run) == :run_warmup
      assert StudyRunner.wire_error(:incompatible_run) == :run_incompatible
      assert StudyRunner.wire_error(:missing_runtime) == :run_not_exportable
      assert StudyRunner.wire_error(:invalid_runtime) == :run_not_exportable
      assert StudyRunner.wire_error(:run_overlap) == :run_overlap
      assert StudyRunner.wire_error(:invalid_result) == :invalid_result
      assert StudyRunner.wire_error({:malformed, "file"}) == :invalid_result
      assert StudyRunner.wire_error(:unknown_reason) == :internal_error
    end
  end

  defp pilot_analysis(metadata_overrides) do
    %{
      metadata:
        %{
          "study_id" => "topology-scale-study",
          "specification_version" => 1,
          "family_scope" => "study",
          "family_size" => 1,
          "command_mode" => "study-pilot",
          "insufficient_pilot" => false,
          "non_informative_comparisons" => [],
          "recommendation" => %{
            "plan_selection_seed_count" => 5,
            "attacks_per_plan" => 10,
            "insufficient_pilot" => false,
            "non_informative_comparisons" => []
          }
        }
        |> Map.merge(metadata_overrides)
    }
  end

  defp single_tier_specification do
    EvaluationFixtures.study_specification()
    |> Map.put("study_id", "topology-scale-study")
    |> Map.put("tiers", ["small"])
  end

  defp two_tier_specification do
    EvaluationFixtures.study_specification()
    |> Map.put("study_id", "topology-scale-study")
    |> Map.put("tiers", ["small", "medium"])
  end

  defp manifest, do: EvaluationFixtures.analysis_manifest()

  defp incompatible_run do
    manifest_id = "study-incompatible-#{System.unique_integer([:positive])}"

    {:ok, _manifest} =
      EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.valid_manifest())

    EvaluationFixtures.completed_run(manifest_id)
  end

  defp final_run do
    manifest_id = "study-final-#{System.unique_integer([:positive])}"

    {:ok, _manifest} =
      EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.final_manifest())

    EvaluationFixtures.completed_run(manifest_id)
  end

  defp expect_analysis(fun) do
    :meck.new(AnalysisClient, [:passthrough])
    on_exit(fn -> :meck.unload() end)

    :meck.expect(AnalysisClient, :analyze_study, fn bundle, study_id, mode ->
      case fun.(bundle, study_id, mode) do
        {:ok, archive} -> {:ok, EvaluationFixtures.result_archive_for_bundle(archive, bundle)}
        error -> error
      end
    end)
  end

  defp expect_unused_analysis do
    expect_analysis(fn _bundle, _study_id, _mode ->
      flunk("the analysis service must not run during preflight")
    end)
  end

  defp drain_phases(acc \\ []) do
    receive do
      {:phase, phase} -> drain_phases([phase | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
