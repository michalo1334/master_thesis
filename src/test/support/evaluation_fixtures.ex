defmodule NetworkDefense.EvaluationFixtures do
  @moduledoc false

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.{EvaluationRuns, PlanPreview}

  alias NetworkDefense.Optimization.{
    ModelVariant,
    OptimizationRun,
    OptimizationRuns,
    SimulationObjective
  }

  alias NetworkDefense.Repo

  def valid_manifest do
    %{
      "schema_version" => 3,
      "model_version" => "current-model-version",
      "id" => "fixed-enterprise-v1",
      "source" => %{
        "type" => "topology",
        "generator" => "enterprise",
        "hosts" => 8,
        "seed" => 42
      },
      "attacker" => %{
        "entry_host" => %{"type" => "semantic_key", "value" => "internet"},
        "max_attempts" => 1
      },
      "model_variants" => [
        %{
          "id" => "full",
          "objective" => "mission_then_blast_radius",
          "require_pre_attack_feasibility" => true
        }
      ],
      "strategy_runs" => [
        %{
          "model_variant" => "full",
          "strategy" => "null",
          "budget" => 1,
          "selection_seeds" => [101]
        },
        %{
          "model_variant" => "full",
          "strategy" => "cvss",
          "budget" => 1,
          "selection_seeds" => [102]
        }
      ],
      "analysis" => %{
        "primary_comparisons" => [
          %{
            "strategy" => "cvss",
            "model_variant" => "full",
            "baseline" => "null",
            "baseline_model_variant" => "full",
            "budget" => 1,
            "outcome" => "blast_radius"
          }
        ],
        "confidence_level" => 0.95,
        "bootstrap_resamples" => 100,
        "permutation_resamples" => 100,
        "multiplicity_correction" => "holm",
        "seed" => 9001
      },
      "evaluation" => %{"trials" => 10, "seed" => 9001}
    }
  end

  @doc """
  Returns one evaluation manifest compatible with the pilot seed schedule.

  Its selection seeds and evaluation seed belong to `pilot_seed_schedule`, so
  a run built from it is Pilot-compatible and Final-incompatible. Tests use
  that asymmetry to prove the two modes cannot share evidence.
  """
  def analysis_manifest do
    study_manifest([101], [201], 9001)
  end

  @doc """
  Returns one evaluation manifest compatible with the final seed schedule.

  Final analysis runs on these runs, never on the Pilot runs.
  """
  def final_manifest do
    study_manifest([301], [401], 9002)
  end

  defp study_manifest(cvss_seeds, simulation_seeds, evaluation_seed) do
    valid_manifest()
    |> Map.put("strategy_runs", [
      %{
        "model_variant" => "full",
        "strategy" => "cvss",
        "budget" => 1,
        "selection_seeds" => cvss_seeds
      },
      %{
        "model_variant" => "full",
        "strategy" => "simulation_informed",
        "budget" => 1,
        "selection_seeds" => simulation_seeds
      }
    ])
    |> put_in(["analysis", "primary_comparisons"], [
      %{
        "strategy" => "simulation_informed",
        "model_variant" => "full",
        "baseline" => "cvss",
        "baseline_model_variant" => "full",
        "budget" => 1,
        "outcome" => "mission_impact"
      }
    ])
    |> put_in(["analysis", "seed"], evaluation_seed)
    |> put_in(["evaluation", "trials"], 3)
    |> put_in(["evaluation", "seed"], evaluation_seed)
  end

  def two_variant_manifest do
    valid_manifest()
    |> put_in(["model_variants"], [
      %{
        "id" => "full",
        "objective" => "mission_then_blast_radius",
        "require_pre_attack_feasibility" => true
      },
      %{
        "id" => "mission_only",
        "objective" => "mission_impact_only",
        "require_pre_attack_feasibility" => true
      }
    ])
    |> Map.put("strategy_runs", [
      %{
        "model_variant" => "full",
        "strategy" => "null",
        "budget" => 1,
        "selection_seeds" => [101]
      },
      %{
        "model_variant" => "full",
        "strategy" => "cvss",
        "budget" => 1,
        "selection_seeds" => [102]
      },
      %{
        "model_variant" => "mission_only",
        "strategy" => "null",
        "budget" => 1,
        "selection_seeds" => [101]
      },
      %{
        "model_variant" => "mission_only",
        "strategy" => "cvss",
        "budget" => 1,
        "selection_seeds" => [102]
      }
    ])
  end

  def canonical_variants do
    Enum.map(ModelVariant.values(), fn variant ->
      definition = ModelVariant.definition(variant)

      %{
        "id" => ModelVariant.to_wire(variant),
        "objective" => SimulationObjective.to_wire(definition.objective),
        "require_pre_attack_feasibility" => definition.require_pre_attack_feasibility
      }
    end)
  end

  def save_manifest(id, content \\ valid_manifest(), title \\ "T") do
    attrs = %{manifest_id: id, title: title, content: Map.put(content, "id", id)}

    case Evaluation.get_by_manifest_id(id) do
      nil -> Evaluation.save(attrs)
      manifest -> Evaluation.save(Map.put(attrs, :existing_manifest_id, manifest.id))
    end
  end

  @doc """
  Returns the study family that `analysis_manifest/0` satisfies.

  The dashboard input-compatibility check compares an evaluation run's
  primary-comparison matrix against this family, so the study fixture and the
  manifest fixture must agree.
  """
  def study_expected_family do
    %{
      "strategies" => ["simulation_informed"],
      "baseline" => "cvss",
      "budgets" => [1],
      "outcome" => "mission_impact"
    }
  end

  def study_specification do
    %{
      "study_id" => "topology-scale-study",
      "specification_version" => 1,
      "tiers" => ["small", "medium", "large"],
      "expected_family" => study_expected_family(),
      "pilot" => %{
        "ci_half_width" => 1.0,
        "plan_count_candidates" => [5, 6, 8],
        "attacks_per_plan_candidates" => [10, 12, 16]
      },
      "multiplicity_correction" => "holm",
      "pilot_seed_schedule" => %{
        "selection" => [101, 201],
        "evaluation" => [9001]
      },
      "final_seed_schedule" => %{
        "selection" => [301, 401],
        "evaluation" => [9002]
      }
    }
  end

  def save_study_specification(content, title \\ "Study specification") do
    Evaluation.save_study_specification(%{title: title, content: content})
  end

  @doc """
  Creates one completed evaluation run for a saved manifest.

  `purpose` defaults to `"evaluation"`. Pass `"warmup"` to create a completed
  warm-up run without running the evaluator.
  """
  def completed_run(manifest_id, purpose \\ "evaluation") do
    {:ok, run} = Evaluation.start(manifest_id)
    run = warmup_run(run, purpose)
    {:ok, completed} = EvaluationRuns.complete(run, 1)
    persist_plan_rows(completed)
    completed
  end

  @doc "Creates one running evaluation run for a saved manifest."
  def running_run(manifest_id) do
    {:ok, run} = Evaluation.start(manifest_id)
    run
  end

  @doc """
  Builds one valid study-analysis result ZIP for the given mode.

  `mode` is `"pilot"` or `"analyze"`. Pass `metadata_overrides` to change the
  recommendation or the pilot stop conditions. Pass `rows_overrides` to
  replace the result rows; the supported keys are `"pilot_results"` and
  `"primary_results"`.
  """
  def study_result_archive(
        mode,
        metadata_overrides \\ %{},
        rows_overrides \\ %{},
        tier_labels \\ ["small"]
      ) do
    metadata =
      %{
        "study_id" => "topology-scale-study",
        "specification_version" => 1,
        "family_scope" => "study",
        "family_size" => length(tier_labels),
        "command_mode" => "study-#{mode}",
        "multiplicity_correction" => "holm",
        "expected_family" => study_expected_family(),
        "tier_labels" => tier_labels,
        "tier_context" => tier_context(tier_labels),
        "uncertainty_sources" => ["attack_outcome"],
        "recommendation" => %{
          "plan_selection_seed_count" => 5,
          "attacks_per_plan" => 10,
          "insufficient_pilot" => false,
          "non_informative_comparisons" => []
        },
        "recommended_plan_selection_seed_count" => 5,
        "recommended_attacks_per_plan" => 10,
        "insufficient_pilot" => false,
        "non_informative_comparisons" => []
      }
      |> Map.merge(metadata_overrides)

    {result_file, default_rows} =
      if mode == "pilot",
        do: {"pilot_results.json", pilot_result_rows(tier_labels)},
        else: {"primary_results.json", primary_result_rows(tier_labels)}

    rows = Map.get(rows_overrides, result_file, default_rows)

    result_files(mode, result_file, metadata, rows)
    |> with_checksums()
    |> zip_files()
  end

  @doc "Builds a result ZIP whose tier context matches a prepared input bundle."
  def study_result_archive_for_bundle(
        mode,
        bundle,
        metadata_overrides \\ %{},
        rows_overrides \\ %{}
      ) do
    tier_context = tier_context_from_bundle(bundle)
    tier_labels = Enum.map(tier_context, & &1["label"])

    study_result_archive(
      mode,
      metadata_overrides
      |> Map.put_new("tier_context", tier_context)
      |> Map.put_new("tier_labels", tier_labels)
      |> Map.put_new("family_size", length(tier_labels)),
      rows_overrides,
      tier_labels
    )
  end

  @doc "Rewrites a result archive with the immutable tier context from its input bundle."
  def result_archive_for_bundle(archive, bundle) do
    with {:ok, entries} <- :zip.extract(archive, [:memory]),
         files <- Map.new(entries, fn {name, content} -> {to_string(name), content} end),
         metadata when is_binary(metadata) <- Map.get(files, "study_metadata.json"),
         {:ok, decoded} <- Jason.decode(metadata),
         context <- tier_context_from_bundle(bundle) do
      if decoded["tier_context"] == context do
        archive
      else
        files
        |> Map.put(
          "study_metadata.json",
          Jason.encode!(Map.put(decoded, "tier_context", context))
        )
        |> with_checksums()
        |> zip_files()
      end
    else
      _error -> archive
    end
  end

  defp tier_context_from_bundle(bundle) do
    {:ok, entries} = :zip.extract(bundle, [:memory])

    entries
    |> Enum.find_value(fn
      {~c"study.json", content} -> Jason.decode!(content)
      _entry -> nil
    end)
    |> Map.fetch!("tiers")
    |> Enum.map(&Map.take(&1, ["label", "archive", "sha256"]))
    |> Enum.map(fn entry ->
      %{
        "label" => entry["label"],
        "archive" => entry["archive"],
        "archive_sha256" => entry["sha256"]
      }
    end)
  end

  @doc "Eligible pilot result: a valid recommendation with no stop condition."
  def pilot_eligible_archive(tier_labels \\ ["small"]),
    do: study_result_archive("pilot", %{}, %{}, tier_labels)

  @doc "Insufficient pilot result: Final stays disabled and Pilot can rerun."
  def pilot_insufficient_archive(tier_labels \\ ["small"]) do
    study_result_archive(
      "pilot",
      %{
        "insufficient_pilot" => true,
        "recommended_plan_selection_seed_count" => nil,
        "recommended_attacks_per_plan" => nil,
        "recommendation" => %{
          "plan_selection_seed_count" => nil,
          "attacks_per_plan" => nil,
          "insufficient_pilot" => true,
          "non_informative_comparisons" => []
        }
      },
      %{},
      tier_labels
    )
  end

  @doc "Non-informative pilot result: one zero-width comparison blocks Final."
  def pilot_non_informative_archive(tier_labels \\ ["small"]) do
    comparisons = Enum.map(tier_labels, &comparison_id/1)

    study_result_archive(
      "pilot",
      %{
        "insufficient_pilot" => true,
        "non_informative_comparisons" => comparisons,
        "recommendation" => %{
          "plan_selection_seed_count" => 5,
          "attacks_per_plan" => 10,
          "insufficient_pilot" => true,
          "non_informative_comparisons" => comparisons
        }
      },
      %{
        "pilot_results.json" =>
          Enum.map(pilot_result_rows(tier_labels), &Map.put(&1, "informative", false))
      },
      tier_labels
    )
  end

  @doc "Final analysis result for the analyze mode."
  def final_archive(tier_labels \\ ["small"]),
    do: study_result_archive("analyze", %{}, %{}, tier_labels)

  @doc """
  Seeds one deterministic end-to-end study scenario.

  Creates one Pilot-compatible completed run and one Final-compatible completed
  run per declared tier, plus one completed warm-up run and one running run.
  The warm-up and running runs must stay out of the tier picker. Saves one
  study specification with the given tiers.
  """
  def seed_study_scenario(tiers \\ ["small", "medium", "large"]) do
    runs = Enum.map(tiers, &completed_tier_run/1)
    final_runs = Enum.map(tiers, &completed_final_tier_run/1)
    warmup_run = completed_warmup_run()
    running_run = running_manifest_run()

    specification =
      study_specification()
      |> Map.put("tiers", tiers)

    {:ok, saved} = save_study_specification(specification)

    %{
      specification: saved,
      runs: runs,
      final_runs: final_runs,
      warmup_run: warmup_run,
      running_run: running_run
    }
  end

  defp completed_tier_run(tier) do
    manifest_id = "study-e2e-#{tier}"
    {:ok, _manifest} = save_manifest(manifest_id, analysis_manifest(), "Tier #{tier} manifest")
    completed_run(manifest_id)
  end

  defp completed_final_tier_run(tier) do
    manifest_id = "study-e2e-final-#{tier}"

    {:ok, _manifest} =
      save_manifest(manifest_id, final_manifest(), "Tier #{tier} final manifest")

    completed_run(manifest_id)
  end

  defp completed_warmup_run do
    manifest_id = "study-e2e-warmup"
    {:ok, _manifest} = save_manifest(manifest_id, analysis_manifest(), "Warm-up manifest")
    completed_run(manifest_id, "warmup")
  end

  defp running_manifest_run do
    manifest_id = "study-e2e-running"
    {:ok, _manifest} = save_manifest(manifest_id, analysis_manifest(), "Running manifest")
    running_run(manifest_id)
  end

  def pilot_result_row(tier \\ "small") do
    %{
      "comparison_id" => comparison_id(tier),
      "tier" => tier,
      "informative" => true,
      "candidate_plan_count" => 5,
      "candidate_attacks_per_plan" => 10,
      "guarded_ci_half_width" => 0.75,
      "target" => 1.0,
      "passes" => true
    }
  end

  def primary_result_row(tier \\ "small") do
    %{
      "comparison" => 0,
      "comparison_id" => comparison_id(tier),
      "tier" => tier,
      "strategy" => "simulation_informed",
      "model_variant" => "full",
      "baseline" => "cvss",
      "baseline_model_variant" => "full",
      "budget" => 1,
      "outcome" => "mission_impact",
      "informative" => true,
      "tested_plan_count" => 5,
      "baseline_plan_count" => 5,
      "attacks_per_plan" => 10,
      "paired_mean_difference" => -1.25,
      "ci_half_width" => 0.4,
      "ci_lower" => -1.65,
      "ci_upper" => -0.85,
      "d_z" => -0.6,
      "p_raw" => 0.01,
      "p_adjusted" => 0.02
    }
  end

  defp pilot_result_rows(tier_labels) do
    for tier <- tier_labels,
        plan_count <- [5, 6, 8],
        attacks_per_plan <- [10, 12, 16] do
      pilot_result_row(tier)
      |> Map.put("candidate_plan_count", plan_count)
      |> Map.put("candidate_attacks_per_plan", attacks_per_plan)
    end
  end

  defp primary_result_rows(tier_labels), do: Enum.map(tier_labels, &primary_result_row/1)

  defp comparison_id(tier),
    do: "#{tier}|full|simulation_informed|full|cvss|1|mission_impact"

  defp tier_context(tier_labels) do
    Enum.map(tier_labels, fn label ->
      %{
        "label" => label,
        "archive" => "tiers/#{label}.zip",
        "archive_sha256" => String.duplicate("a", 64)
      }
    end)
  end

  defp result_files("pilot", result_file, metadata, rows) do
    %{
      "study_metadata.json" => Jason.encode!(metadata),
      "pilot_results.csv" => "",
      result_file => Jason.encode!(rows)
    }
  end

  defp result_files("analyze", result_file, metadata, rows) do
    %{
      "study_metadata.json" => Jason.encode!(metadata),
      "primary_results.csv" => "",
      result_file => Jason.encode!(rows),
      "tier_context.json" => Jason.encode!(metadata["tier_context"])
    }
  end

  defp with_checksums(files) do
    payload = Map.delete(files, "checksums.txt")

    checksums =
      payload
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("\n", fn {name, content} ->
        digest = Base.encode16(:crypto.hash(:sha256, content), case: :lower)
        "#{name}  #{digest}"
      end)
      |> then(&(&1 <> "\n"))

    Map.put(payload, "checksums.txt", checksums)
  end

  @doc "Builds one in-memory ZIP archive from a name-to-content map."
  def zip_files(files) do
    entries = Enum.map(files, fn {name, content} -> {String.to_charlist(name), content} end)
    {:ok, {_name, archive}} = :zip.create(~c"study-results.zip", entries, [:memory])
    archive
  end

  # Study compatibility reads these persisted rows because they are the exact
  # source of `plans.jsonl`, not a reconstruction from the manifest.
  defp persist_plan_rows(run) do
    run.resolved_manifest
    |> PlanPreview.plans()
    |> Enum.each(fn {model_variant, strategy, budget, selection_seed} ->
      {:ok, _plan} =
        OptimizationRun.new(%{
          graph_revision_id: run.source_graph_revision_id,
          evaluation_run_id: run.id,
          model_variant: model_variant,
          strategy: strategy,
          requested_budget: budget,
          selection_seed: selection_seed
        })
        |> OptimizationRuns.create()
    end)
  end

  defp warmup_run(run, "warmup"),
    do: Repo.update!(Ecto.Changeset.change(run, purpose: "warmup"))

  defp warmup_run(run, _purpose), do: run
end
