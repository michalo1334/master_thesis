# Prespecified calibration runner for the Evaluation2 matching-based kernel.
#
# Scope: the complete statistical protocol of
# `docs/inprogress/evaluation2-statistical-checks.md` (sections 2 to 5) executed
# against the production numerical kernel. No database, Gust, Oban, endpoint, or
# simulation service is started, and no mock or Python implementation is used.
#
#   MIX_ENV=test mix run --no-start scripts/evaluation2_calibration.exs --dry-run
#   MIX_ENV=test mix run --no-start scripts/evaluation2_calibration.exs --protocol [--output PATH]
#   MIX_ENV=test mix run --no-start scripts/evaluation2_calibration.exs --profile N [--sections LIST] [--output PATH]
#
# `--protocol` runs the declared grid: 1000 datasets per scenario/count cell,
# 1000 family replicates per family cell, and 100 planning repetitions. `--profile`
# reduces every replicate count to N and is explicitly NOT evidence.
#
# This file is a scaffold plus working plumbing: the owner inspects it, completes
# substantive logic, profiles runtime, and runs the full protocol. It makes no
# calibration claim.

# The production kernel compiles with EXLA on the host client, so the numeric
# library and its compiler application must be running. No database, service, or
# web application starts.
{:ok, _} = Application.ensure_all_started(:nx)
{:ok, _} = Application.ensure_all_started(:exla)
Code.require_file("evaluation2_calibration_models.exs", __DIR__)

unless Code.ensure_loaded?(NetworkDefense.Evaluation2Test.NumericAnchors) do
  Code.require_file("../test/support/evaluation2_numeric_anchors.ex", __DIR__)
end

defmodule Evaluation2.Calibration do
  @moduledoc """
  Prespecified calibration harness for the native matching-based kernel.

  The harness declares the grid, the error-check count `J`, and every threshold
  before the first dataset exists. Section 1 reports raw-null size, coverage of
  the true effect, and family error; section 2 reports Pilot planning behaviour.
  Rates carry binomial (Wilson) uncertainty and a one-sided exact binomial tail
  against the diagnostic threshold `0.01 / J`.

  Interval-reporting claims stay with the Grid section, which runs the complete
  kernel path including interval inversion. Family error uses the raw capital
  p-value path and omits inversion for runtime, as the protocol permits; the
  inverted path can only raise a p-value through the conservative empty-inversion
  fallback, so omitting it cannot hide a family error.
  """

  alias Evaluation2.CalibrationModels, as: Models

  alias NetworkDefense.Evaluation2.Study.{Compute, Definition}
  alias NetworkDefense.Evaluation2.Study.Compute.{Betting, Input}

  alias NetworkDefense.Evaluation2.Study.Definition.{
    Candidate,
    Graph,
    Pilot,
    Precision,
    SampleSize,
    Strategy
  }

  alias NetworkDefense.Evaluation2.Study.Pilot.{Analysis, Assessment}
  alias NetworkDefense.Evaluation2Test.NumericAnchors, as: Anchor

  ## Declared protocol constants. Frozen before any result is inspected.

  @seed 20_261_030
  @confidence 0.95
  # Declared literal so the reported nominal rate stays exactly 0.05.
  @confidence_error 0.05
  @family_alpha 0.05
  @family_size 6
  @raw_thresholds [0.05, 0.01, 0.05 / 6]
  @raw_threshold_labels ["0.05", "0.01", "family-first 0.05/6"]
  @counts [{5, 10}, {20, 40}, {100, 200}]
  @family_shapes [{20, 40}, {100, 200}]
  @family_models [:deterministic, :mixed]
  @family_cases [:global_null, :partial_null]
  @pilot_candidates [{5, 10}, {20, 40}, {40, 80}]
  @extra_capacities [{0, 0}, {20, 40}]
  @planning_kinds [:deterministic, :mixed]
  @outer_subsamples 32
  @guard_quantile 0.9
  @target_half_width 0.2
  @lower_bound 0.0
  @upper_bound 1.0
  @datasets_per_cell 1000
  @family_replicates 1000
  @planning_replicates 100
  # Documented constant-contrast arithmetic probe of the method record.
  @anchor_probe_p 0.0008718
  @anchor_relative_tolerance 1.0e-9
  @anchor_pairs 160
  @log_tiny -1.0e308
  @wilson_z 1.959_963_984_540_054

  @null_scenarios [
    %{name: "deterministic_d0", model: :deterministic, d: 0.0, p: nil, b: nil, effect: 0.0},
    %{name: "rare_rows_p0.1", model: :rare_rows, d: nil, p: 0.1, b: nil, effect: 0.0},
    %{name: "rare_rows_p0.01", model: :rare_rows, d: nil, p: 0.01, b: nil, effect: 0.0},
    %{name: "attack_only_d0", model: :attack_only, d: 0.0, p: nil, b: nil, effect: 0.0},
    %{name: "cancellation", model: :cancellation, d: nil, p: nil, b: nil, effect: 0.0},
    %{name: "interaction_d0", model: :interaction, d: 0.0, p: nil, b: nil, effect: 0.0},
    %{name: "mixed_b-0.1_d0", model: :mixed, d: 0.0, p: nil, b: -0.1, effect: 0.0},
    %{name: "mixed_b+0.1_d0", model: :mixed, d: 0.0, p: nil, b: 0.1, effect: 0.0}
  ]

  @effect_scenarios [
    %{name: "deterministic_d-0.1", model: :deterministic, d: -0.1, p: nil, b: nil, effect: -0.1},
    %{name: "deterministic_d+0.1", model: :deterministic, d: 0.1, p: nil, b: nil, effect: 0.1},
    %{name: "attack_only_d-0.1", model: :attack_only, d: -0.1, p: nil, b: nil, effect: -0.1},
    %{name: "attack_only_d+0.1", model: :attack_only, d: 0.1, p: nil, b: nil, effect: 0.1},
    %{name: "interaction_d-0.1", model: :interaction, d: -0.1, p: nil, b: nil, effect: -0.1},
    %{name: "interaction_d+0.1", model: :interaction, d: 0.1, p: nil, b: nil, effect: 0.1},
    %{name: "mixed_b-0.1_d-0.1", model: :mixed, d: -0.1, p: nil, b: -0.1, effect: -0.1},
    %{name: "mixed_b-0.1_d+0.1", model: :mixed, d: 0.1, p: nil, b: -0.1, effect: 0.1},
    %{name: "mixed_b+0.1_d-0.1", model: :mixed, d: -0.1, p: nil, b: 0.1, effect: -0.1},
    %{name: "mixed_b+0.1_d+0.1", model: :mixed, d: 0.1, p: nil, b: 0.1, effect: 0.1}
  ]

  @scenarios @null_scenarios ++ @effect_scenarios

  # J is the predeclared count of error/coverage checks. Size checks apply to the
  # true-null scenarios only; coverage checks apply to every scenario; family
  # error checks cover both family models, both null cases, and both shapes.
  @size_checks length(@null_scenarios) * length(@counts) * length(@raw_thresholds)
  @coverage_checks length(@scenarios) * length(@counts)
  @family_error_checks length(@family_models) * length(@family_cases) * length(@family_shapes)
  @j @size_checks + @coverage_checks + @family_error_checks
  @diagnostic_threshold 0.01 / @j

  ## Entry point

  def main(argv) do
    options = arguments!(argv)
    assert_headless!()

    metadata = metadata(options)
    declaration = declaration(options)
    IO.puts(header(options, metadata, declaration))

    case options.mode do
      :dry_run ->
        emit(options.output, %{
          "runner" => "evaluation2_calibration",
          "mode" => "dry-run",
          "evidence" => false,
          "metadata" => metadata,
          "declaration" => declaration,
          "limitations" => limitations()
        })

        IO.puts("Nothing executed. The declaration above is the predeclared protocol.")

      _ ->
        record(options.output, %{
          "record" => "header",
          "mode" => describe_mode(options),
          "metadata" => metadata,
          "declaration" => declaration
        })

        stream_audit =
          Models.audit_streams(
            @scenarios,
            @counts,
            protocol_count(:grid),
            @family_shapes,
            protocol_count(:family),
            Enum.map(@extra_capacities, &pool_shape/1),
            protocol_count(:planning)
          )

        record(options.output, %{"record" => "stream_audit", "audit" => stream_audit})
        results = run_sections(options)

        summary =
          summary(options, metadata, declaration, results)
          |> Map.put("stream_audit", stream_audit)

        emit(options.output, summary)
        report(summary)
    end
  end

  ## Arguments

  defp arguments!(argv) do
    {mode, rest} = mode!(argv)
    {sections, rest} = sections!(rest)
    {output, rest} = output!(rest, nil)

    unless rest == [] do
      raise ArgumentError, "unexpected arguments: #{inspect(rest)}"
    end

    if mode == :protocol and Enum.sort(sections) != Enum.sort(all_sections()),
      do:
        raise(
          ArgumentError,
          "--protocol requires all sections; use --profile for partial plumbing checks"
        )

    if mode == :protocol and is_nil(output),
      do: raise(ArgumentError, "--protocol requires --output to retain the complete report")

    if output && (File.exists?(output) or File.exists?(output <> ".jsonl")),
      do: raise(ArgumentError, "output must be a new path; existing reports stay immutable")

    %{mode: mode, sections: sections, output: output}
  end

  defp mode!(["--protocol" | rest]), do: {:protocol, rest}
  defp mode!(["--dry-run" | rest]), do: {:dry_run, rest}

  defp mode!(["--profile", count | rest]) do
    case Integer.parse(count) do
      {value, ""} when value > 0 -> {{:profile, value}, rest}
      _invalid -> raise ArgumentError, "--profile needs a positive integer"
    end
  end

  defp mode!(argv) do
    raise ArgumentError,
          "declare exactly one mode: --protocol, --dry-run, or --profile N (got #{inspect(argv)})"
  end

  defp sections!(argv) do
    case Enum.split_while(argv, &(&1 != "--sections")) do
      {rest, []} ->
        {all_sections(), rest}

      {rest, ["--sections", list | after_list]} ->
        sections =
          list
          |> String.split(",", trim: true)
          |> Enum.map(&section!/1)
          |> Enum.uniq()

        if sections == [], do: raise(ArgumentError, "--sections needs at least one section")
        {Enum.sort(sections), rest ++ after_list}

      {_rest, _partial} ->
        raise ArgumentError, "--sections needs a value"
    end
  end

  defp section!("grid"), do: :grid
  defp section!("family"), do: :family
  defp section!("planning"), do: :planning
  defp section!(other), do: raise(ArgumentError, "unknown section #{inspect(other)}")

  defp all_sections, do: [:grid, :family, :planning]

  defp output!(argv, _default) do
    case Enum.split_while(argv, &(&1 != "--output")) do
      {rest, []} ->
        {nil, rest}

      {rest, ["--output", path | after_path]} ->
        if path == "", do: raise(ArgumentError, "--output needs a path")
        {path, rest ++ after_path}

      {_rest, _partial} ->
        raise ArgumentError, "--output needs a value"
    end
  end

  ## Runtime isolation

  defp assert_headless! do
    started = Application.started_applications() |> Enum.map(&elem(&1, 0)) |> MapSet.new()

    leaked =
      [
        :network_defense,
        :oban,
        :gust,
        :postgrex,
        :ecto_sql,
        NetworkDefense.Repo,
        Gust.Repo
      ]
      |> Enum.filter(fn subject ->
        cond do
          is_atom(subject) and subject in [:network_defense, :oban, :gust, :postgrex, :ecto_sql] ->
            MapSet.member?(started, subject)

          is_atom(subject) ->
            Process.whereis(subject) != nil

          true ->
            false
        end
      end)

    if leaked != [] do
      raise "calibration runner needs a database-free run: #{inspect(leaked)} is running"
    end
  end

  ## Metadata and declaration

  defp metadata(options) do
    %{
      "runner" => "scripts/evaluation2_calibration.exs",
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "nx" => app_version(:nx),
      "decimal" => app_version(:decimal),
      "jason" => app_version(:jason),
      "backend" => inspect(Nx.default_backend()),
      "kernel_compiler" => "EXLA 1.0.0, client :host (fixed by the kernel)",
      "exla" => app_version(:exla),
      "mix_lock_sha256" => digest("mix.lock"),
      "kernel_source_sha256" => kernel_digest(),
      "model_generator_sha256" => digest("scripts/evaluation2_calibration_models.exs"),
      "runner_sha256" => digest("scripts/evaluation2_calibration.exs"),
      "seed_policy_sha256" => digest("lib/network_defense/evaluation2/study/randomness.ex"),
      "planning_policy_sha256" =>
        digest("lib/network_defense/evaluation2/study/pilot/analysis.ex"),
      "independent_oracle_sha256" => digest("test/support/evaluation2_numeric_anchors.ex"),
      "git_commit" => git_commit(),
      "network_defense_started" => app_started?(:network_defense),
      "repos_started" => %{
        "network_defense" => Process.whereis(NetworkDefense.Repo) != nil,
        "gust" => Process.whereis(Gust.Repo) != nil
      },
      "mode" => describe_mode(options),
      "evidence" => options.mode == :protocol,
      "utc_started" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "seed" => @seed,
      "generator" => %{
        "family" => "Erlang exsss per derived SHA-256 root",
        "derivation" => "Study.Randomness.root(seed, declared role context)",
        "roles" => "separate row and shared-column streams per purpose/cell/replicate/phase",
        "determinism" => "same arguments reproduce the same matrices"
      }
    }
  end

  defp describe_mode(%{mode: :protocol, sections: sections}),
    do: "full protocol, sections #{inspect(sections)}"

  defp describe_mode(%{mode: {:profile, count}, sections: sections}),
    do: "PROFILE ONLY (not evidence): #{count} replicates, sections #{inspect(sections)}"

  defp describe_mode(%{mode: :dry_run, sections: sections}),
    do: "dry run, sections #{inspect(sections)}"

  defp declaration(options) do
    %{
      "protocol_source" => "docs/inprogress/evaluation2-statistical-checks.md",
      "seed" => @seed,
      "confidence_level" => @confidence,
      "confidence_error" => @confidence_error,
      "family_alpha" => @family_alpha,
      "family_size" => @family_size,
      "raw_rejection_thresholds" => @raw_thresholds,
      "counts" => Enum.map(@counts, &Tuple.to_list/1),
      "datasets_per_cell" => declared_replicates(options, :grid),
      "family_shapes" => Enum.map(@family_shapes, &Tuple.to_list/1),
      "family_models" => Enum.map(@family_models, &to_string/1),
      "family_cases" => Enum.map(@family_cases, &to_string/1),
      "family_replicates" => declared_replicates(options, :family),
      "planning_replicates" => declared_replicates(options, :planning),
      "pilot_candidates" => Enum.map(@pilot_candidates, &Tuple.to_list/1),
      "extra_capacities" => Enum.map(@extra_capacities, &Tuple.to_list/1),
      "planning_kinds" => Enum.map(@planning_kinds, &to_string/1),
      "outer_subsamples" => @outer_subsamples,
      "guard_quantile" => @guard_quantile,
      "target_half_width" => @target_half_width,
      "planner_cost_coefficients" => %{
        "plan" => 1,
        "simulation" => 1,
        "shared_reference" => "counted once per family"
      },
      "outcome_range" => [@lower_bound, @upper_bound],
      "grid_scenarios" => Enum.map(@scenarios, &scenario_declaration/1),
      "check_count" => %{
        "J" => @j,
        "size" => @size_checks,
        "coverage" => @coverage_checks,
        "family_error" => @family_error_checks,
        "formula" =>
          "size=#{length(@null_scenarios)} null scenarios * #{length(@counts)} counts * #{length(@raw_thresholds)} thresholds; " <>
            "coverage=#{length(@scenarios)} scenarios * #{length(@counts)} counts; " <>
            "family=#{length(@family_models)} models * #{length(@family_cases)} cases * #{length(@family_shapes)} shapes",
        "diagnostic_threshold" => @diagnostic_threshold,
        "declared_before_data" => true,
        "planning_attainment_is_performance_not_error_check" => true,
        "family_power_is_descriptive_not_error_check" => true
      },
      "declared_replicates_note" =>
        "declared_replicates equals the protocol count in full protocol mode"
    }
  end

  defp scenario_declaration(scenario) do
    %{
      "name" => scenario.name,
      "model" => to_string(scenario.model),
      "d" => scenario.d,
      "p" => scenario.p,
      "b" => scenario.b,
      "true_effect" => scenario.effect,
      "null" => scenario.effect == 0.0
    }
  end

  defp declared_replicates(%{mode: :protocol}, section), do: protocol_count(section)
  defp declared_replicates(%{mode: {:profile, count}}, _section), do: count
  defp declared_replicates(%{mode: :dry_run}, section), do: protocol_count(section)

  # Only the protocol declares the full replicate counts; profile mode declares
  # its reduced count and stays labelled not-evidence.
  defp protocol_count(:grid), do: @datasets_per_cell
  defp protocol_count(:family), do: @family_replicates
  defp protocol_count(:planning), do: @planning_replicates

  defp replicates(%{mode: :protocol} = options, section),
    do: declared_replicates(options, section)

  defp replicates(%{mode: {:profile, count}}, _section), do: count
  defp replicates(%{mode: :dry_run}, _section), do: 0

  ## Sections

  defp run_sections(options) do
    result = %{grid: nil, family: nil, planning: nil}

    result =
      if :grid in options.sections,
        do: %{result | grid: run_grid(replicates(options, :grid), options.output)},
        else: result

    result =
      if :family in options.sections,
        do: %{result | family: run_family(replicates(options, :family), options.output)},
        else: result

    if :planning in options.sections,
      do: %{result | planning: run_planning(replicates(options, :planning), options.output)},
      else: result
  end

  ## Section 2: controlled crossed-data grid

  defp run_grid(count, output) do
    for scenario <- @scenarios, shape <- @counts do
      cell = grid_cell(scenario, shape, count)
      record(output, cell)
      cell
    end
  end

  defp grid_cell(scenario, {rows, columns} = shape, count) do
    started = System.monotonic_time(:millisecond)

    totals =
      Enum.reduce(0..(count - 1), initial_cell_totals(), fn replicate, totals ->
        {alternative, reference} = Models.dataset(scenario, shape, replicate)

        result =
          compare!(
            alternative,
            reference,
            "#{scenario.name} #{rows}x#{columns} replicate #{replicate}"
          )

        accumulate_cell(totals, result, scenario.effect)
      end)

    elapsed = System.monotonic_time(:millisecond) - started

    checks =
      if scenario.effect == 0.0 do
        for {threshold, label, successes} <-
              Enum.zip([
                @raw_thresholds,
                @raw_threshold_labels,
                totals.rejections
              ]) do
          check(
            "size:#{scenario.name}:#{rows}x#{columns}:#{label}",
            "grid",
            "#{scenario.name} #{rows}x#{columns} raw rejection at #{label}",
            successes,
            count,
            threshold
          )
        end
      else
        []
      end

    coverage =
      check(
        "coverage:#{scenario.name}:#{rows}x#{columns}",
        "grid",
        "#{scenario.name} #{rows}x#{columns} interval excludes true effect #{scenario.effect}",
        totals.excludes,
        count,
        @confidence_error
      )

    power =
      if scenario.effect == 0.0 do
        []
      else
        for {_threshold, label, successes} <-
              Enum.zip([@raw_thresholds, @raw_threshold_labels, totals.rejections]) do
          descriptive(
            "power:#{scenario.name}:#{rows}x#{columns}:#{label}",
            "grid",
            "#{scenario.name} #{rows}x#{columns} raw rejection at #{label}",
            successes,
            count
          )
        end
      end

    %{
      "kind" => "grid_cell",
      "scenario" => scenario.name,
      "model" => to_string(scenario.model),
      "counts" => [rows, columns],
      "true_effect" => scenario.effect,
      "null" => scenario.effect == 0.0,
      "replicates" => count,
      "elapsed_ms" => elapsed,
      "mean_estimate" => round6(totals.estimate_sum / count),
      "mean_half_width" => round6(totals.half_width_sum / count),
      "informative" => totals.informative,
      "non_informative" => count - totals.informative,
      "checks" => checks ++ [coverage],
      "descriptive" => power
    }
  end

  defp initial_cell_totals do
    %{
      rejections: Enum.map(@raw_thresholds, fn _ -> 0 end),
      excludes: 0,
      informative: 0,
      estimate_sum: 0.0,
      half_width_sum: 0.0
    }
  end

  defp accumulate_cell(totals, result, effect) do
    rejections =
      Enum.zip(@raw_thresholds, totals.rejections)
      |> Enum.map(fn {threshold, count} ->
        if result.p_value <= threshold, do: count + 1, else: count
      end)

    excludes =
      if result.lower > effect or result.upper < effect,
        do: totals.excludes + 1,
        else: totals.excludes

    %{
      rejections: rejections,
      excludes: excludes,
      informative: totals.informative + if(result.informative, do: 1, else: 0),
      estimate_sum: totals.estimate_sum + result.estimate,
      half_width_sum: totals.half_width_sum + result.half_width
    }
  end

  ## Section 4: family behaviour and the deterministic 36-member anchor

  defp run_family(count, output) do
    configs =
      for model <- @family_models, null_case <- @family_cases, shape <- @family_shapes do
        config = family_config(model, null_case, shape, count)
        record(output, config)
        config
      end

    %{"anchor" => family_anchor(), "configs" => configs}
  end

  defp family_config(model, null_case, {rows, columns}, count) do
    true_positions =
      if null_case == :global_null,
        do: Enum.to_list(0..(@family_size - 1)),
        else: Models.family_true_null_positions()

    false_positions =
      if null_case == :global_null, do: [], else: Models.family_false_null_positions()

    started = System.monotonic_time(:millisecond)

    totals =
      Enum.reduce(
        0..(count - 1),
        %{
          family_errors: 0,
          false_rejections: List.duplicate(0, @family_size),
          families_all_false_rejected: 0
        },
        fn replicate, totals ->
          pairs = Models.family(model, null_case, {rows, columns}, replicate)

          p_values =
            Enum.map(pairs, fn {alternative, reference} -> raw_p_value(alternative, reference) end)

          corrected = Compute.holm(p_values, @family_alpha)

          family_error = Enum.any?(true_positions, &Enum.at(corrected, &1).reject?)
          false_hits = Enum.count(false_positions, &Enum.at(corrected, &1).reject?)

          all_false_rejected =
            false_positions != [] and false_hits == length(false_positions)

          %{
            family_errors: totals.family_errors + if(family_error, do: 1, else: 0),
            false_rejections:
              Enum.zip(totals.false_rejections, corrected)
              |> Enum.map(fn {hits, member} -> hits + if(member.reject?, do: 1, else: 0) end),
            families_all_false_rejected:
              totals.families_all_false_rejected + if(all_false_rejected, do: 1, else: 0)
          }
        end
      )

    elapsed = System.monotonic_time(:millisecond) - started

    error_check =
      check(
        "family_error:#{model}:#{null_case}:#{rows}x#{columns}",
        "family",
        "#{model} #{null_case} #{rows}x#{columns}: any true-null member rejected",
        totals.family_errors,
        count,
        @family_alpha
      )

    descriptive =
      if false_positions == [] do
        []
      else
        Enum.map(false_positions, fn position ->
          descriptive(
            "family_power:#{model}:#{null_case}:#{rows}x#{columns}:position#{position}",
            "family",
            "#{model} #{null_case} #{rows}x#{columns}: false-null comparison #{position} rejected",
            Enum.at(totals.false_rejections, position),
            count
          )
        end) ++
          [
            descriptive(
              "family_power_joint:#{model}:#{null_case}:#{rows}x#{columns}",
              "family",
              "#{model} #{null_case} #{rows}x#{columns}: every false-null member rejected",
              totals.families_all_false_rejected,
              count
            )
          ]
      end

    %{
      "kind" => "family_config",
      "model" => to_string(model),
      "null_case" => to_string(null_case),
      "counts" => [rows, columns],
      "replicates" => count,
      "true_null_positions" => true_positions,
      "false_null_positions" => false_positions,
      "elapsed_ms" => elapsed,
      "checks" => [error_check],
      "descriptive" => descriptive,
      "p_value_path" => "raw capital p-value; interval inversion omitted",
      "shared_reference" => "C = 0.5 + 0.2 V_j, shared across the six comparisons",
      "coefficients" => "row coefficient alternating +0.1/-0.1, column +0.1, interaction 0.1"
    }
  end

  defp family_anchor do
    alternative = Models.constant(@anchor_pairs, @anchor_pairs, 0.4)
    reference = Models.constant(@anchor_pairs, @anchor_pairs, 0.5)
    result = compare!(alternative, reference, "deterministic anchor")

    corrected =
      Compute.holm([result.p_value | List.duplicate(1.0, @family_size * 6 - 1)], @family_alpha)

    oracle = Anchor.constant_contrast(-0.1, 1.0, @anchor_pairs, @confidence)
    deviation = abs(result.p_value - oracle.p_value) / oracle.p_value

    unless deviation <= @anchor_relative_tolerance and hd(corrected).reject? and
             not Enum.any?(tl(corrected), & &1.reject?),
           do: raise("independent 160-pair/Holm anchor failed")

    %{
      "kind" => "deterministic_anchor",
      "pairs_per_matching" => @anchor_pairs,
      "family_members" => @family_size * 6,
      "alpha" => @family_alpha,
      "kernel_p_value" => result.p_value,
      "documented_probe_p" => @anchor_probe_p,
      "independent_oracle_p" => oracle.p_value,
      "relative_deviation" => round6(deviation),
      "probe_agrees" => deviation <= @anchor_relative_tolerance,
      "first_position_rejects" => hd(corrected).reject?,
      "other_members_reject" => Enum.any?(tl(corrected), & &1.reject?),
      "interval" => [result.lower, result.upper],
      "note" => "deterministic anchor; it is not a replicate of any reported rate",
      "oracle" =>
        "behavior-test support module holds the independent oracle; this anchor cross-checks the documented probe and the Holm decision"
    }
  end

  ## Section 4: Pilot planning experiment

  defp run_planning(count, output) do
    for kind <- @planning_kinds, extra <- @extra_capacities do
      pool = pool_shape(extra)

      repetitions =
        for repetition <- 0..(count - 1) do
          planning_repetition(kind, extra, pool, repetition)
        end

      config = summarize_planning(kind, extra, pool, repetitions, count)
      # Full per-repetition detail goes to the incremental stream; the summary
      # keeps the selection and attainment record without the assessment bulk.
      record(output, Map.put(config, "repetition_outcomes", repetitions))

      Map.put(
        config,
        "repetition_outcomes",
        Enum.map(repetitions, &Map.drop(&1, ["assessments"]))
      )
    end
  end

  # Pilot pool is the coordinate-wise maximum candidate plus the declared extra
  # capacity, matching the native `pilot_capacity` rule.
  defp pool_shape({extra_plans, extra_attacks}) do
    plans = @pilot_candidates |> Enum.map(&elem(&1, 0)) |> Enum.max()
    attacks = @pilot_candidates |> Enum.map(&elem(&1, 1)) |> Enum.max()
    {plans + extra_plans, attacks + extra_attacks}
  end

  defp planning_repetition(kind, extra, pool, repetition) do
    started = System.monotonic_time(:millisecond)
    pilot = Models.planning_family(kind, pool, repetition, :pilot, pool)

    assessments =
      for {{plans, attacks}, position} <- Enum.with_index(@pilot_candidates),
          {{alternative, reference}, comparison} <- Enum.with_index(pilot) do
        seed = Models.planning_seed(kind, pool, repetition, comparison)
        input = input(alternative, reference)

        {:ok, result} =
          Compute.pilot_precision(
            input,
            %{plans: plans, attacks: attacks},
            %{outer_subsamples: @outer_subsamples, guard_quantile: @guard_quantile},
            inference(),
            seed
          )

        %{
          candidate_position: position,
          plans: plans,
          attacks: attacks,
          comparison: comparison,
          guarded_half_width: result.guarded_half_width,
          informative: result.informative,
          passes: result.informative and result.guarded_half_width <= @target_half_width
        }
      end

    selection = select_candidate(assessments)
    selected = selection.selected

    final_pairs =
      Models.planning_family(kind, {selected.plans, selected.attacks}, repetition, :final, pool)

    final =
      Enum.map(final_pairs, fn {alternative, reference} ->
        compare!(
          alternative,
          reference,
          "planning #{kind} capacity #{inspect(extra)} repetition #{repetition} final"
        )
      end)

    attainment = Enum.map(final, &(&1.half_width <= @target_half_width))

    %{
      "kind" => "planning_repetition",
      "family" => to_string(kind),
      "extra_capacity" => Tuple.to_list(extra),
      "pool_counts" => Tuple.to_list(pool),
      "repetition" => repetition,
      "outcome" => selection.outcome,
      "override" => selection.override,
      "selected_counts" => [selected.plans, selected.attacks],
      "selected_position" => selection.position,
      "elapsed_ms" => System.monotonic_time(:millisecond) - started,
      "per_comparison_attained" => attainment,
      "joint_attained" => Enum.all?(attainment),
      "final_half_widths" => Enum.map(final, &round6(&1.half_width)),
      "assessments" =>
        Enum.map(assessments, fn assessment ->
          %{
            "candidate_position" => assessment.candidate_position,
            "counts" => [assessment.plans, assessment.attacks],
            "comparison" => assessment.comparison,
            "guarded_half_width" => round6(assessment.guarded_half_width),
            "informative" => assessment.informative,
            "passes" => assessment.passes
          }
        end)
    }
  end

  # Use the production fan-in and selector. Three physical groups each own n
  # plan rows: two alternatives and their single shared reference.
  defp select_candidate(assessments) do
    native =
      Enum.map(assessments, fn a ->
        %Assessment{
          candidate_position: a.candidate_position,
          comparison_position: a.comparison,
          guarded_half_width: a.guarded_half_width,
          informative: a.informative,
          passes: a.passes
        }
      end)

    {:ok, output} =
      Analysis.summarize(planning_definition(), native, %{plan_ms: [1.0], attack_ms: [1.0]})

    case output.outcome.outcome do
      :insufficient ->
        # Explicit insufficient override: keep the largest declared candidate and
        # report that the precision target is given up.
        {plans, attacks} = Enum.at(@pilot_candidates, length(@pilot_candidates) - 1)

        %{
          outcome: "insufficient_override",
          override: true,
          selected: %{plans: plans, attacks: attacks},
          position: length(@pilot_candidates) - 1
        }

      :recommended ->
        selected = output.outcome

        position =
          Enum.find_index(
            planning_definition().pilot.candidates,
            &(&1.id == selected.candidate_id)
          )

        %{
          outcome: "recommended",
          override: false,
          selected: %{plans: selected.plan_count_per_side, attacks: selected.attacks_per_plan},
          position: position
        }
    end
  end

  defp planning_definition do
    %Definition{
      tiers: [
        %Graph{
          tier: "small",
          budgets: [1],
          alternatives: [%Strategy{key: :random}, %Strategy{key: :simulation_informed}]
        }
      ],
      pilot: %Pilot{
        candidates:
          Enum.with_index(@pilot_candidates, fn {plans, attacks}, i ->
            %Candidate{id: "candidate-#{i}", plans: plans, attacks: attacks}
          end),
        extra_pool: %SampleSize{plans: 0, attacks: 0},
        precision: %Precision{
          outer_subsamples: @outer_subsamples,
          guard_quantile: @guard_quantile,
          target_half_width: @target_half_width
        }
      }
    }
  end

  defp summarize_planning(kind, extra, pool, repetitions, count) do
    outcomes = Enum.frequencies_by(repetitions, & &1["outcome"])
    selected = Enum.frequencies_by(repetitions, fn repetition -> selected_key(repetition) end)

    per_comparison =
      for comparison <- 0..(length(Models.planning_effects()) - 1) do
        successes =
          Enum.count(repetitions, fn repetition ->
            Enum.at(repetition["per_comparison_attained"], comparison)
          end)

        descriptive(
          "planning_attainment:#{kind}:#{inspect(extra)}:comparison#{comparison}",
          "planning",
          "#{kind} pool #{inspect(pool)}: comparison #{comparison} half width <= #{@target_half_width} on fresh Final data",
          successes,
          count
        )
      end

    joint =
      descriptive(
        "planning_attainment:#{kind}:#{inspect(extra)}:joint",
        "planning",
        "#{kind} pool #{inspect(pool)}: every comparison attains #{@target_half_width} on fresh Final data",
        Enum.count(repetitions, & &1["joint_attained"]),
        count
      )

    %{
      "kind" => "planning_config",
      "family" => to_string(kind),
      "extra_capacity" => Tuple.to_list(extra),
      "pool_counts" => Tuple.to_list(pool),
      "repetitions" => count,
      "outcomes" => outcomes,
      "outcome_uncertainty" =>
        Enum.map(["recommended", "insufficient_override"], fn outcome ->
          descriptive(
            "planning_outcome:#{kind}:#{inspect(extra)}:#{outcome}",
            "planning",
            outcome,
            Map.get(outcomes, outcome, 0),
            count
          )
        end),
      "selected_counts" => selected,
      "selected_count_uncertainty" =>
        Enum.map(@pilot_candidates, fn {plans, attacks} ->
          key = "#{plans}x#{attacks}"

          descriptive(
            "planning_selection:#{kind}:#{inspect(extra)}:#{key}",
            "planning",
            key,
            Map.get(selected, key, 0),
            count
          )
        end),
      "attainment_by_approval" =>
        Enum.map(["recommended", "insufficient_override"], fn outcome ->
          group = Enum.filter(repetitions, &(&1["outcome"] == outcome))

          %{
            outcome: outcome,
            n: length(group),
            joint:
              if(group == [],
                do: nil,
                else:
                  descriptive(
                    "planning_stratum:#{kind}:#{inspect(extra)}:#{outcome}",
                    "planning",
                    outcome,
                    Enum.count(group, & &1["joint_attained"]),
                    length(group)
                  )
              )
          }
        end),
      "override_total" => Enum.count(repetitions, & &1["override"]),
      "descriptive" => per_comparison ++ [joint],
      "checks" => [],
      "guarded_width_is_heuristic" =>
        "the finite-pool guard quantile is a planning heuristic; it is not a fresh-sample success probability",
      "full_pool_note" =>
        "an extra capacity of zero makes the largest candidate use the whole pool, so its outer subsets differ only by order",
      "override_consequence" =>
        "the insufficient override gives up the declared precision target and reports that cost"
    }
  end

  # A separate, predeclared small-candidate probe exercises an explicit override
  # even when all main planning repetitions recommend a larger candidate.
  defp override_probe do
    definition = planning_definition()

    definition = %{
      definition
      | pilot: %{definition.pilot | candidates: [hd(definition.pilot.candidates)]}
    }

    pairs = Models.planning_family(:deterministic, {5, 10}, 0, :pilot, {5, 10})

    assessments =
      Enum.with_index(pairs, fn {alternative, reference}, position ->
        {:ok, result} =
          Compute.pilot_precision(
            input(alternative, reference),
            %{plans: 5, attacks: 10},
            %{outer_subsamples: @outer_subsamples, guard_quantile: @guard_quantile},
            inference(),
            Models.planning_seed(:deterministic, {5, 10}, 0, position)
          )

        %Assessment{
          candidate_position: 0,
          comparison_position: position,
          guarded_half_width: result.guarded_half_width,
          informative: result.informative,
          passes: result.informative and result.guarded_half_width <= @target_half_width
        }
      end)

    {:ok, output} =
      Analysis.summarize(definition, assessments, %{plan_ms: [1.0], attack_ms: [1.0]})

    unless output.outcome.outcome == :insufficient,
      do: raise("override probe must be insufficient")

    final =
      Models.planning_family(:deterministic, {5, 10}, 0, :final, {5, 10})
      |> Enum.map(fn {a, c} -> compare!(a, c, "explicit insufficient override") end)

    %{
      pilot_outcome: "insufficient",
      explicit_override: true,
      selected_counts: [5, 10],
      target_half_width: @target_half_width,
      final_half_widths: Enum.map(final, & &1.half_width),
      precision_target_relinquished: true,
      actual_application_approval_covered_by: "FLOW-02 integration and separate real study"
    }
  end

  defp selected_key(repetition),
    do: repetition["selected_counts"] |> Enum.map_join("x", &Integer.to_string/1)

  ## Statistics

  defp check(id, section, label, successes, count, nominal) do
    unless successes <= count do
      raise "check #{id} counts #{successes} successes above #{count} datasets"
    end

    rate = successes / count
    {low, high} = wilson(successes, count)
    log_tail = log_binomial_tail(count, successes, nominal)
    tail = if log_tail <= @log_tiny, do: 0.0, else: :math.exp(log_tail)
    excess = rate > nominal

    %{
      "id" => id,
      "section" => to_string(section),
      "error_check" => true,
      "label" => label,
      "successes" => successes,
      "n" => count,
      "rate" => round6(rate),
      "wilson_lower" => round6(low),
      "wilson_upper" => round6(high),
      "nominal_upper_rate" => nominal,
      "log_binomial_tail" => round6(log_tail),
      "binomial_tail_p" => tail,
      "excess" => excess,
      "flagged" => excess and log_tail < :math.log(@diagnostic_threshold)
    }
  end

  defp descriptive(id, section, label, successes, count) do
    {low, high} = wilson(successes, count)

    %{
      "id" => id,
      "section" => to_string(section),
      "error_check" => false,
      "label" => label,
      "successes" => successes,
      "n" => count,
      "rate" => round6(successes / count),
      "wilson_lower" => round6(low),
      "wilson_upper" => round6(high)
    }
  end

  # Wilson score interval at 95 percent; descriptive binomial uncertainty.
  defp wilson(successes, count) do
    rate = successes / count
    z2 = @wilson_z * @wilson_z
    denominator = 1 + z2 / count
    centre = (rate + z2 / (2 * count)) / denominator

    spread =
      @wilson_z * :math.sqrt(rate * (1 - rate) / count + z2 / (4 * count * count)) / denominator

    {max(centre - spread, 0.0), min(centre + spread, 1.0)}
  end

  # Exact one-sided binomial tail P(X >= k) in log space.
  defp log_binomial_tail(_count, successes, _nominal) when successes <= 0, do: 0.0
  defp log_binomial_tail(_count, _successes, nominal) when nominal >= 1.0, do: 0.0
  defp log_binomial_tail(_count, _successes, nominal) when nominal <= 0.0, do: @log_tiny
  defp log_binomial_tail(count, successes, _nominal) when successes > count, do: @log_tiny

  defp log_binomial_tail(count, successes, nominal) do
    log_base =
      log_choose(count, successes) + successes * :math.log(nominal) +
        (count - successes) * :math.log(1 - nominal)

    log_base + :math.log(relative_tail(count, successes, nominal, log_base))
  end

  defp relative_tail(count, successes, _nominal, _log_base) when successes >= count, do: 1.0

  defp relative_tail(count, successes, nominal, log_base) do
    ratio_scale = nominal / (1 - nominal)

    {sum, _log} =
      Enum.reduce(successes..(count - 1), {1.0, log_base}, fn index, {sum, log_pmf} ->
        next = log_pmf + :math.log((count - index) / (index + 1) * ratio_scale)
        {sum + :math.exp(next - log_base), next}
      end)

    sum
  end

  defp log_choose(count, successes),
    do: log_factorial(count) - log_factorial(successes) - log_factorial(count - successes)

  defp log_factorial(0), do: 0.0
  defp log_factorial(value), do: Enum.reduce(1..value, 0.0, fn i, acc -> acc + :math.log(i) end)

  ## Kernel calls

  defp compare!(alternative, reference, context) do
    case Compute.compare(input(alternative, reference), inference()) do
      {:ok, result} -> result
      {:error, reason} -> raise "kernel rejected #{context}: #{inspect(reason)}"
    end
  end

  # Raw capital p-value without interval inversion. The conservative
  # empty-inversion fallback raises p to one, so this path cannot hide a family
  # error; the Grid section covers the inverted path on the same models.
  defp raw_p_value(alternative, reference) do
    {:ok, prepared} = Input.prepare(input(alternative, reference))

    case prepared do
      %{matchings: nil} ->
        1.0

      %{matchings: matchings, estimate: estimate} ->
        matchings
        |> Betting.prepare(@confidence_error)
        |> Betting.p_value(estimate)
    end
  end

  defp input(alternative, reference),
    do: %{
      alternative: alternative,
      reference: reference,
      lower_bound: @lower_bound,
      upper_bound: @upper_bound
    }

  defp inference, do: %{confidence_level: @confidence}

  ## Reporting

  defp summary(options, metadata, declaration, results) do
    checks = collect_checks(results)
    descriptive = collect_descriptive(results)

    expected =
      if(results.grid, do: length(@scenarios) * length(@counts), else: 0) +
        if(results.grid,
          do: length(@null_scenarios) * length(@counts) * length(@raw_thresholds),
          else: 0
        ) +
        if results.family,
          do: length(@family_models) * length(@family_cases) * length(@family_shapes),
          else: 0

    flagged = Enum.filter(checks, & &1["flagged"])

    %{
      "runner" => "evaluation2_calibration",
      "mode" => to_string(elem_mode(options.mode)),
      "evidence" => options.mode == :protocol,
      "evidence_label" =>
        if(options.mode == :protocol,
          do: "declared protocol replicate counts",
          else: "NOT EVIDENCE: reduced profile replicate counts"
        ),
      "metadata" => metadata,
      "declaration" => declaration,
      "grid" => results.grid,
      "family" => results.family,
      "planning" => results.planning,
      "explicit_insufficient_override" => if(results.planning, do: override_probe(), else: nil),
      "checks" => checks,
      "descriptive" => descriptive,
      "check_audit" => %{
        "declared_J" => @j,
        "expected_checks_this_run" => expected,
        "emitted_checks" => length(checks),
        "consistent" => length(checks) == expected,
        "sections" => Enum.map(options.sections, &to_string/1)
      },
      "flags" => %{
        "total" => length(flagged),
        "ids" => Enum.map(flagged, & &1["id"]),
        "rule" => "rate above the nominal upper rate and exact binomial tail below 0.01/J",
        "consequence" =>
          "a flag requires investigation; it does not authorize widening bands, dropping a scenario, or tuning on the same results"
      },
      "calibration_status" =>
        "NOT A CALIBRATION RESULT: this runner records evidence only; no pass is claimed by the scaffold",
      "limitations" => limitations(),
      "utc_finished" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp elem_mode(:protocol), do: "protocol"
  defp elem_mode(:dry_run), do: "dry-run"
  defp elem_mode({:profile, count}), do: "profile-#{count}"

  defp collect_checks(results) do
    grid =
      (results.grid || [])
      |> Enum.flat_map(& &1["checks"])

    family =
      case results.family do
        nil -> []
        %{"configs" => configs} -> Enum.flat_map(configs, & &1["checks"])
      end

    planning =
      (results.planning || [])
      |> Enum.flat_map(& &1["checks"])

    grid ++ family ++ planning
  end

  defp collect_descriptive(results) do
    grid = (results.grid || []) |> Enum.flat_map(& &1["descriptive"])

    family =
      case results.family do
        nil -> []
        %{"configs" => configs} -> Enum.flat_map(configs, & &1["descriptive"])
      end

    planning = (results.planning || []) |> Enum.flat_map(& &1["descriptive"])
    grid ++ family ++ planning
  end

  defp report(summary) do
    IO.puts(
      "\nDeclared J #{summary["check_audit"]["declared_J"]} | emitted #{summary["check_audit"]["emitted_checks"]} | " <>
        "consistent #{summary["check_audit"]["consistent"]}"
    )

    IO.puts("\nError and coverage checks (rate, Wilson 95%, exact tail, flag)")

    summary["checks"]
    |> Enum.each(fn check ->
      IO.puts(
        "  #{check["id"]} = #{check["successes"]}/#{check["n"]} = #{check["rate"]} " <>
          "Wilson [#{check["wilson_lower"]}, #{check["wilson_upper"]}] nominal #{check["nominal_upper_rate"]} " <>
          "tail #{check["binomial_tail_p"]}#{if check["flagged"], do: " FLAG", else: ""}"
      )
    end)

    IO.puts("\nDescriptive rates (power, family power, planning attainment)")

    summary["descriptive"]
    |> Enum.each(fn record ->
      IO.puts(
        "  #{record["id"]} = #{record["successes"]}/#{record["n"]} = #{record["rate"]} " <>
          "Wilson [#{record["wilson_lower"]}, #{record["wilson_upper"]}]"
      )
    end)

    IO.puts(
      "\nFlags: #{summary["flags"]["total"]}#{if summary["flags"]["total"] > 0, do: " (investigation required)"}"
    )

    IO.puts("""

    #{summary["calibration_status"]}
    Evidence: #{summary["evidence_label"]}
    Limitations:
    #{Enum.map_join(summary["limitations"], "\n", &"      - #{&1}")}
    """)
  end

  defp limitations do
    [
      "This file is a scaffold for the Goal 06 protocol; a scaffold pass is not calibration evidence.",
      "The full protocol needs a real run with the declared counts (1000 / 1000 / 100). Profile runs are labelled not-evidence.",
      "Family error uses the raw capital path without interval inversion; the conservative empty-inversion fallback can only raise p, so this path cannot hide a family error.",
      "Planning attainment uses the same confidence level as Final by construction; the guard quantile stays a heuristic for fresh Final data.",
      "Wilson intervals are descriptive binomial uncertainty; they are not simultaneous bands across checks.",
      "The check-flag rule controls diagnostic false alarms only; it is separate from the study Holm procedure.",
      "A deterministic anchor with 160 constant pairs is reported for orientation; it is not a replication of any rate.",
      "Elixir/Python-free: only the native Compute, Betting, Input, Intervals and Pilot planning modules run here."
    ]
  end

  ## Output

  defp emit(nil, _document), do: :ok

  defp emit(path, document) do
    File.write!(path, Jason.encode!(document, pretty: true) <> "\n")
    file = path <> ".jsonl"

    File.write!(file, Jason.encode!(Map.drop(document, ["grid", "family", "planning"])) <> "\n", [
      :append
    ])

    IO.puts("Wrote #{path} and #{file}")
  end

  defp record(nil, _document), do: :ok

  defp record(path, document) do
    File.write!(path <> ".jsonl", Jason.encode!(document) <> "\n", [:append])
    :ok
  end

  ## Metadata helpers

  defp app_version(app) do
    case Application.spec(app, :vsn) do
      nil -> "unavailable"
      version -> to_string(version)
    end
  end

  defp app_started?(app),
    do: Enum.any?(Application.started_applications(), &(elem(&1, 0) == app))

  defp digest(path) do
    case File.read(path) do
      {:ok, contents} -> sha256(contents)
      {:error, _reason} -> "unavailable"
    end
  end

  defp sha256(contents), do: Base.encode16(:crypto.hash(:sha256, contents), case: :lower)

  # Identity of the numerical source under test.
  defp kernel_digest do
    [
      "lib/network_defense/evaluation2/study/compute.ex"
      | Path.wildcard("lib/network_defense/evaluation2/study/compute/*.ex")
    ]
    |> Enum.sort()
    |> Enum.map_join("\n", &File.read!/1)
    |> sha256()
  end

  defp git_commit do
    {output, 0} = System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true)
    String.trim(output)
  rescue
    _error -> "unavailable"
  end

  defp header(options, metadata, declaration) do
    """
    ==========================================================================
    Evaluation2 prespecified calibration runner
    Mode: #{describe_mode(options)} | evidence: #{options.mode == :protocol}
    Kernel: #{inspect(Compute)} | seed #{@seed} | confidence #{@confidence}
    Kernel compiler: #{metadata["kernel_compiler"]} | nx #{metadata["nx"]} | exla #{metadata["exla"]}
    Declared J: #{declaration["check_count"]["J"]} | diagnostic threshold #{declaration["check_count"]["diagnostic_threshold"]}
    ==========================================================================
    """
  end

  defp round6(value) when is_float(value), do: Float.round(value, 6)
  defp round6(value), do: value
end

Evaluation2.Calibration.main(System.argv())
