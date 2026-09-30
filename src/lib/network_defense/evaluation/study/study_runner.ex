defmodule NetworkDefense.Evaluation.StudyRunner do
  @moduledoc """
  Focused study-analysis operations.

  `prepare/3` validates the study-specification JSON, the tier selection, and
  the mode seed schedule, exports one completed archive per declared tier, and
  builds the deterministic study bundle. `submit/2` sends a prepared bundle to
  the analysis service. The Mix task,
  `NetworkDefense.Evaluation.analyze_study/3`, and the dashboard LiveView call
  these functions so CLI and browser execution cannot drift.

  Pilot and Final select separate tier runs. The mode decides which declared
  seed schedule every mapped run must satisfy. Listing and preflight accept
  the same mode, so the picker and the bundle cannot disagree.

  Preflight stops after bundle construction and never calls the analysis
  service. Execution repeats the full validation through the same
  `prepare/2` step before it submits.

  Wire mode values are strings. `parse_mode/1` maps them to the internal mode
  atoms and never creates atoms from arbitrary input. Domain errors map to
  stable wire codes in `wire_error/1`.
  """

  alias NetworkDefense.Evaluation.AnalysisClient
  alias NetworkDefense.Evaluation.AnalysisLimits
  alias NetworkDefense.Evaluation.AnalysisResult
  alias NetworkDefense.Evaluation.Contracts.StudySpecification, as: StudySpecificationContract
  alias NetworkDefense.Evaluation.EvaluationManifest
  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Evaluation.EvaluationRuns
  alias NetworkDefense.Evaluation.OutputContract
  alias NetworkDefense.Evaluation.PlanPreview
  alias NetworkDefense.Evaluation.StudyAttempt
  alias NetworkDefense.Evaluation.StudyBundle
  alias NetworkDefense.Evaluation.StudyInputCompatibility
  alias NetworkDefense.Evaluation.StudySpecification
  alias NetworkDefense.Evaluation.StudySpecifications
  alias NetworkDefense.Evaluation.StudyTierValidator
  alias NetworkDefense.Graph.GraphRevision
  alias NetworkDefense.Observability

  @type mode :: :pilot | :final

  @type phase ::
          :building_bundle
          | :submitting_analysis
          | :waiting_for_service
          | :validating_result
          | :complete

  @type tier_run :: {String.t(), String.t()}

  @type tier_run_input ::
          tier_run()
          | %{required(:tier) => String.t(), required(:run_id) => String.t()}

  @type prepared :: %{
          bundle: binary(),
          study_id: String.t(),
          specification_version: pos_integer() | nil,
          tier_runs: [tier_run()],
          tier_labels: [String.t()],
          expected_family: map(),
          tier_context: [map()],
          expected_results: map()
        }

  @type preflight :: %{
          study_id: String.t(),
          specification_version: pos_integer() | nil,
          tier_labels: [String.t()],
          bundle_bytes: non_neg_integer()
        }

  @type lifecycle_event :: :started | :completed | :failed | :cancelled

  @phases [
    :building_bundle,
    :submitting_analysis,
    :waiting_for_service,
    :validating_result,
    :complete
  ]

  @lifecycle_event [:network_defense, :evaluation, :study_runner]

  @wire_errors %{
    invalid_request: :invalid_request,
    invalid_mode: :invalid_mode,
    invalid_study_spec: :invalid_specification,
    invalid_specification: :invalid_specification,
    specification_not_found: :specification_not_found,
    invalid_tier: :invalid_tier_selection,
    invalid_study_tiers: :invalid_tier_selection,
    unsafe_tier_label: :unsafe_tier_label,
    duplicate_tier_label: :duplicate_tier_label,
    duplicate_run_id: :duplicate_run_id,
    run_overlap: :run_overlap,
    invalid_run_id: :invalid_run_id,
    no_tiers: :no_tiers,
    not_found: :run_not_found,
    incomplete: :run_incomplete,
    not_exportable: :run_not_exportable,
    missing_runtime: :run_not_exportable,
    invalid_runtime: :run_not_exportable,
    warmup_run: :run_warmup,
    incompatible_run: :run_incompatible,
    missing_plan_selection_seeds: :run_incompatible,
    invalid_result: :invalid_result,
    tier_declaration_mismatch: :tier_declaration_mismatch,
    tier_archive_too_large: :tier_archive_too_large,
    input_too_large: :input_too_large,
    output_too_large: :output_too_large,
    result_too_large: :result_too_large,
    final_not_available: :final_not_available,
    already_running: :already_running,
    document_locked: :document_locked,
    document_not_found: :document_not_found,
    not_configured: :not_configured,
    transport: :transport,
    http_status: :http_status,
    content_type: :content_type,
    response_too_large: :response_too_large,
    invalid_body: :invalid_body,
    cancelled: :cancelled,
    internal_error: :internal_error,
    invalid_zip: :invalid_result,
    member_too_large: :invalid_result,
    archive_too_large: :invalid_result,
    unexpected_member: :invalid_result,
    invalid_checksum: :invalid_result,
    checksum_mismatch: :invalid_result,
    missing_or_duplicate: :invalid_result,
    missing_field: :invalid_result,
    malformed_field: :invalid_result,
    malformed_row: :invalid_result,
    malformed_runtime_summary: :invalid_result
  }

  @doc "Returns the named study phases in execution order."
  @spec phases() :: [phase()]
  def phases, do: @phases

  @spec parse_mode(String.t()) :: {:ok, mode()} | {:error, :invalid_mode}
  def parse_mode("pilot"), do: {:ok, :pilot}
  def parse_mode("final"), do: {:ok, :final}
  def parse_mode(_mode), do: {:error, :invalid_mode}

  @spec mode_to_wire(mode()) :: String.t()
  def mode_to_wire(:pilot), do: "pilot"
  def mode_to_wire(:final), do: "final"

  @spec phase_to_wire(phase()) :: String.t()
  def phase_to_wire(phase) when phase in @phases, do: Atom.to_string(phase)

  @doc """
  Maps one domain error to one stable wire error code.
  """
  @spec wire_error(term()) :: atom()
  def wire_error(reason) when is_atom(reason), do: Map.get(@wire_errors, reason, :internal_error)
  def wire_error({:zip, _reason}), do: :internal_error
  def wire_error({_tag, _detail}), do: :invalid_result
  def wire_error(_reason), do: :internal_error

  @spec emit_lifecycle(lifecycle_event(), map()) :: :ok
  def emit_lifecycle(event, metadata) when event in [:started, :completed, :failed, :cancelled] do
    :telemetry.execute(@lifecycle_event, %{count: 1}, Map.put(metadata, :event, event))
    :ok
  end

  @doc """
  Emits one terminal lifecycle event for a consumed attempt.

  The owner calls this only when it consumes an attempt, so one attempt causes
  at most one terminal event. A queued result and a later `:DOWN`, or a close
  after a consumed result, cannot emit two terminal events. The event carries
  the attempt duration, so the crash path reports a failed duration too.
  """
  @spec emit_attempt_lifecycle(:completed | :failed | :cancelled, StudyAttempt.t(), map()) :: :ok
  def emit_attempt_lifecycle(outcome, %StudyAttempt{} = attempt, metadata)
      when outcome in [:completed, :failed, :cancelled] do
    metadata =
      metadata
      |> Map.put(:mode, mode_to_wire(attempt.mode))
      |> Map.put(:duration_ms, Observability.duration_ms(attempt.started_at))

    emit_lifecycle(outcome, metadata)
  end

  @doc """
  Lists exportable completed, non-warm-up evaluation runs for one declared tier.

  The saved specification must declare `tier`, so a request cannot list runs
  for a tier the locked mapping will reject. Preflight reads the same
  specification, so the picker and the bundle agree.
  """
  @spec list_tier_runs(String.t(), String.t(), mode()) :: {:ok, [map()]} | {:error, term()}
  def list_tier_runs(specification_id, tier, mode)
      when is_binary(specification_id) and is_binary(tier) do
    with {:ok, schedule_mode} <- schedule_mode(mode),
         {:ok, specification} <- fetch_specification(specification_id),
         :ok <- require_declared_tier(specification, tier),
         {:ok, shape} <- required_shape(specification) do
      runs =
        EvaluationRuns.list_eligible_study_runs()
        |> Enum.reject(&warm_up?/1)
        |> Enum.filter(&eligible_run?(&1, shape, schedule_mode))
        |> Enum.map(&tier_run_summary/1)

      {:ok, runs}
    end
  end

  def list_tier_runs(_specification_id, _tier, _mode), do: {:error, :invalid_tier}

  @doc """
  Returns one concise required-input-shape summary for a saved specification.

  The tier picker and the run tab show this summary, so a user sees the
  evaluation-run shape the specification demands before choosing a run.
  """
  @spec required_inputs(String.t()) :: {:ok, String.t()} | {:error, term()}
  def required_inputs(specification_id) when is_binary(specification_id) do
    with {:ok, specification} <- fetch_specification(specification_id),
         {:ok, shape} <- required_shape(specification) do
      {:ok, StudyInputCompatibility.summary(shape)}
    end
  end

  def required_inputs(_specification_id), do: {:error, :specification_not_found}

  defp required_shape(%StudySpecification{content: content}) do
    with {:ok, validated} <- StudySpecificationContract.validate(content) do
      StudyInputCompatibility.shape(validated)
    end
  end

  defp warm_up?(%EvaluationRun{purpose: "warmup"}), do: true
  defp warm_up?(_run), do: false

  defp eligible_run?(run, shape, mode) do
    with true <- OutputContract.exportable?(run),
         {:ok, seeds} <- OutputContract.plan_selection_seeds(run) do
      StudyInputCompatibility.mode_compatible?(run, shape, mode, seeds)
    else
      _ineligible -> false
    end
  end

  defp require_declared_tier(%StudySpecification{content: content}, tier) do
    case StudySpecificationContract.describe(content) do
      {:ok, %{tiers: tiers}} when is_list(tiers) ->
        if tier in tiers, do: :ok, else: {:error, :tier_declaration_mismatch}

      {:error, _errors} ->
        {:error, :invalid_study_spec}
    end
  end

  @spec preflight(String.t(), [tier_run_input()], mode()) ::
          {:ok, preflight()} | {:error, term()}
  def preflight(specification_id, tier_runs, mode) do
    with {:ok, prepared} <- prepare_specification(specification_id, tier_runs, mode) do
      {:ok,
       %{
         study_id: prepared.study_id,
         specification_version: prepared.specification_version,
         tier_labels: prepared.tier_labels,
         bundle_bytes: byte_size(prepared.bundle)
       }}
    end
  end

  @doc """
  Resolves one saved specification version and builds its study bundle.
  """
  @spec prepare_specification(String.t(), [tier_run_input()], mode() | :analyze) ::
          {:ok, prepared()} | {:error, term()}
  def prepare_specification(specification_id, tier_runs, mode) when is_binary(specification_id) do
    with {:ok, specification} <- fetch_specification(specification_id) do
      prepare(tier_runs, specification.content, mode)
    end
  end

  def prepare_specification(_specification_id, _tier_runs, _mode),
    do: {:error, :specification_not_found}

  @doc """
  Validates the tier selection and the study specification, then builds the
  deterministic study bundle. It never calls the analysis service.
  """
  @spec prepare([tier_run_input()], map(), mode() | :analyze) ::
          {:ok, prepared()} | {:error, term()}
  def prepare(tier_runs, study_spec, mode) do
    with {:ok, schedule_mode} <- schedule_mode(mode),
         {:ok, tier_runs} <- validate_tier_runs(tier_runs),
         {:ok, study_spec} <- validate_study_spec(study_spec, tier_runs),
         {:ok, shape} <- StudyInputCompatibility.shape(study_spec),
         {:ok, tiers} <- export_tiers(tier_runs),
         :ok <- validate_inputs(tiers, shape, schedule_mode),
         {:ok, expected_results} <- expected_results(tiers, study_spec, shape),
         {:ok, bundle} <- StudyBundle.archive(tiers, study_spec) do
      {:ok,
       %{
         bundle: bundle,
         study_id: study_spec["study_id"],
         specification_version: study_spec["specification_version"],
         tier_runs: tier_runs,
         tier_labels: tier_labels(tier_runs),
         expected_family: StudyInputCompatibility.family(shape),
         tier_context: tier_context(tiers),
         expected_results: expected_results
       }}
    end
  end

  @doc """
  Prepares a bundle from an in-memory specification and submits it.

  `on_phase` receives one `phase/0` value before each execution boundary.
  """
  @spec analyze([tier_run_input()], map(), mode() | :analyze, (phase() -> any())) ::
          {:ok, binary()} | {:error, term()}
  def analyze(tier_runs, study_spec, mode, on_phase \\ &noop_phase/1) do
    case run_steps(on_phase, fn -> prepare(tier_runs, study_spec, mode) end, mode) do
      {:ok, {_prepared, archive}} -> {:ok, archive}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Runs a saved specification end to end: rebuild the bundle, submit, and parse.

  The locked `specification_id` and `tier_runs` are revalidated before
  submission. `on_phase` receives one `phase/0` value before each boundary.
  """
  @spec execute(String.t(), [tier_run_input()], mode(), (phase() -> any())) ::
          {:ok, %{archive: binary(), analysis: map()}} | {:error, term()}
  def execute(specification_id, tier_runs, mode, on_phase \\ &noop_phase/1) do
    with {:ok, {prepared, archive}} <-
           run_steps(
             on_phase,
             fn -> prepare_specification(specification_id, tier_runs, mode) end,
             mode
           ),
         :ok <- notify(on_phase, :validating_result),
         {:ok, analysis} <- parse_result(archive),
         :ok <- verify_result(mode, prepared, analysis) do
      notify(on_phase, :complete)
      {:ok, %{archive: archive, analysis: analysis}}
    end
  end

  @doc """
  Binds a parsed service result to the locked prepared session.

  The service result must match the exact locked command mode, study identity,
  specification version, `study` family scope, expected family, and declared
  tier labels. A mismatch returns `{:error, :invalid_result}` before the
  caller stores eligibility or delivers the archive.
  """
  @spec verify_result(mode() | :analyze, prepared(), map()) :: :ok | {:error, :invalid_result}
  def verify_result(mode, prepared, analysis) do
    with %{} = metadata <- analysis_metadata(analysis),
         :ok <- match_command_mode(metadata, mode),
         :ok <- match_value(metadata["study_id"], prepared.study_id),
         :ok <-
           match_value(
             metadata["specification_version"],
             prepared.specification_version
           ),
         :ok <- match_value(metadata["family_scope"], "study"),
         :ok <- match_value(metadata["family_size"], prepared.expected_results.family_size),
         :ok <- match_value(metadata["multiplicity_correction"], "holm"),
         :ok <- match_expected_family(metadata["expected_family"], prepared.expected_family),
         :ok <- match_tier_labels(metadata["tier_labels"], prepared.tier_labels),
         :ok <- match_tier_context(metadata["tier_context"], prepared.tier_context),
         :ok <- match_result_rows(mode, analysis, prepared.expected_results) do
      :ok
    else
      _mismatch -> {:error, :invalid_result}
    end
  end

  defp analysis_metadata(%{metadata: %{} = metadata}), do: metadata
  defp analysis_metadata(%{"metadata" => %{} = metadata}), do: metadata
  defp analysis_metadata(_analysis), do: nil

  defp match_command_mode(metadata, mode) do
    match_value(metadata["command_mode"], command_mode(mode))
  end

  defp command_mode(:pilot), do: "study-pilot"
  defp command_mode(:final), do: "study-analyze"
  defp command_mode(:analyze), do: "study-analyze"
  defp command_mode(_mode), do: nil

  defp match_value(value, value), do: :ok
  defp match_value(_left, _right), do: {:error, :mismatch}

  defp match_expected_family(declared, expected) when is_map(declared) and is_map(expected) do
    match_value(project_family(declared), project_family(expected))
  end

  defp match_expected_family(_declared, _expected), do: {:error, :mismatch}

  defp project_family(%{} = family) do
    %{
      "strategies" => Map.get(family, "strategies"),
      "baseline" => Map.get(family, "baseline"),
      "budgets" => Map.get(family, "budgets"),
      "outcome" => Map.get(family, "outcome")
    }
  end

  defp match_tier_labels(declared, expected) when is_list(declared) and is_list(expected) do
    match_value(Enum.sort(declared), Enum.sort(expected))
  end

  defp match_tier_labels(_declared, _expected), do: {:error, :mismatch}

  defp match_tier_context(declared, expected) when is_list(declared) and is_list(expected) do
    with {:ok, declared} <- normalize_tier_context(declared),
         {:ok, expected} <- normalize_tier_context(expected),
         :ok <- match_value(declared, expected) do
      :ok
    else
      _mismatch -> {:error, :mismatch}
    end
  end

  defp match_tier_context(_declared, _expected), do: {:error, :mismatch}

  defp match_result_rows(mode, analysis, expected) when mode in [:final, :analyze] do
    exact_primary_rows(Map.get(analysis, :primary_results), expected.primary_rows)
  end

  defp match_result_rows(:pilot, analysis, expected) do
    exact_pilot_rows(Map.get(analysis, :pilot_results), expected.pilot_tuples)
  end

  defp match_result_rows(_mode, _analysis, _expected), do: {:error, :mismatch}

  defp exact_primary_rows(rows, expected_rows) when is_list(rows) and is_map(expected_rows) do
    rows
    |> Enum.reduce_while({:ok, MapSet.new()}, fn row, {:ok, seen} ->
      case Map.fetch(expected_rows, row["comparison_id"]) do
        {:ok, expected} ->
          add_primary_row(row, expected, seen)

        _mismatch ->
          {:halt, :error}
      end
    end)
    |> exact_members(Map.keys(expected_rows))
  end

  defp exact_primary_rows(_rows, _expected_rows), do: {:error, :mismatch}

  defp add_primary_row(row, expected, seen) do
    id = row["comparison_id"]

    if Map.take(row, Map.keys(expected)) == expected and not MapSet.member?(seen, id),
      do: {:cont, {:ok, MapSet.put(seen, id)}},
      else: {:halt, :error}
  end

  defp exact_pilot_rows(rows, expected_tuples) when is_list(rows) do
    rows
    |> Enum.reduce_while({:ok, MapSet.new()}, fn row, {:ok, seen} ->
      tuple =
        {row["comparison_id"], row["tier"], row["candidate_plan_count"],
         row["candidate_attacks_per_plan"]}

      if MapSet.member?(expected_tuples, tuple) and not MapSet.member?(seen, tuple) do
        {:cont, {:ok, MapSet.put(seen, tuple)}}
      else
        {:halt, :error}
      end
    end)
    |> exact_members(expected_tuples)
  end

  defp exact_pilot_rows(_rows, _expected_tuples), do: {:error, :mismatch}

  defp exact_members({:ok, actual}, expected) do
    if MapSet.equal?(actual, MapSet.new(expected)), do: :ok, else: {:error, :mismatch}
  end

  defp exact_members(:error, _expected), do: {:error, :mismatch}

  defp expected_results(tiers, study_spec, shape) do
    with {:ok, primary_rows} <- expected_primary_rows(tiers),
         :ok <- expected_primary_count(primary_rows, tiers, shape),
         {:ok, pilot_tuples} <- expected_pilot_tuples(primary_rows, study_spec) do
      {:ok,
       %{
         family_size: map_size(primary_rows),
         primary_rows: primary_rows,
         pilot_tuples: pilot_tuples
       }}
    end
  end

  defp expected_primary_rows(tiers) do
    Enum.reduce_while(tiers, {:ok, %{}}, fn tier, {:ok, rows} ->
      case merge_tier_primary_rows(rows, tier) do
        {:ok, merged} -> {:cont, {:ok, merged}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp merge_tier_primary_rows(rows, tier) do
    with {:ok, tier_rows} <- tier_primary_rows(tier) do
      merged = Map.merge(rows, tier_rows)

      if map_size(merged) == map_size(rows) + map_size(tier_rows),
        do: {:ok, merged},
        else: {:error, :invalid_study_spec}
    end
  end

  defp tier_primary_rows(%{tier: tier, run: %{resolved_manifest: manifest}})
       when is_binary(tier) and is_map(manifest) do
    manifest
    |> get_in(["analysis", "primary_comparisons"])
    |> collect_tier_primary_rows(tier)
  end

  defp tier_primary_rows(_tier), do: {:error, :invalid_study_spec}

  defp collect_tier_primary_rows([_first | _rest] = comparisons, tier) do
    Enum.reduce_while(comparisons, {:ok, %{}}, fn comparison, {:ok, rows} ->
      case put_expected_primary_row(rows, tier, comparison) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp collect_tier_primary_rows(_comparisons, _tier), do: {:error, :invalid_study_spec}

  defp put_expected_primary_row(rows, tier, comparison) do
    with {:ok, row} <- expected_primary_row(tier, comparison) do
      id = row["comparison_id"]

      if is_map_key(rows, id),
        do: {:error, :invalid_study_spec},
        else: {:ok, Map.put(rows, id, row)}
    end
  end

  defp expected_primary_row(tier, %{} = comparison) do
    with {:ok, model_variant} <- expected_text(comparison["model_variant"]),
         {:ok, strategy} <- expected_text(comparison["strategy"]),
         {:ok, baseline} <- expected_text(comparison["baseline"]),
         {:ok, baseline_model_variant} <- expected_text(comparison["baseline_model_variant"]),
         {:ok, budget} <- expected_positive_integer(comparison["budget"]),
         {:ok, outcome} <- expected_text(comparison["outcome"]) do
      identity = %{
        "tier" => tier,
        "model_variant" => model_variant,
        "strategy" => strategy,
        "baseline" => baseline,
        "baseline_model_variant" => baseline_model_variant,
        "budget" => budget,
        "outcome" => outcome
      }

      {:ok,
       Map.put(
         identity,
         "comparison_id",
         Enum.join(
           [
             tier,
             model_variant,
             strategy,
             baseline_model_variant,
             baseline,
             Integer.to_string(budget),
             outcome
           ],
           "|"
         )
       )}
    end
  end

  defp expected_primary_row(_tier, _comparison), do: {:error, :invalid_study_spec}

  defp expected_primary_count(primary_rows, tiers, %{pairs: pairs}) do
    expected_count = length(tiers) * MapSet.size(pairs)
    if map_size(primary_rows) == expected_count, do: :ok, else: {:error, :invalid_study_spec}
  end

  defp expected_pilot_tuples(primary_rows, study_spec) do
    with %{} = pilot <- Map.get(study_spec, "pilot"),
         plan_counts when is_list(plan_counts) and plan_counts != [] <-
           pilot["plan_count_candidates"],
         attack_counts when is_list(attack_counts) and attack_counts != [] <-
           pilot["attacks_per_plan_candidates"],
         true <- Enum.all?(plan_counts, &positive_integer?/1),
         true <- Enum.all?(attack_counts, &positive_integer?/1) do
      tuples =
        for %{"comparison_id" => id, "tier" => tier} <- Map.values(primary_rows),
            plan_count <- plan_counts,
            attacks_per_plan <- attack_counts,
            into: MapSet.new() do
          {id, tier, plan_count, attacks_per_plan}
        end

      {:ok, tuples}
    else
      _invalid -> {:error, :invalid_study_spec}
    end
  end

  defp expected_text(value) when is_binary(value) and value != "", do: {:ok, value}
  defp expected_text(_value), do: {:error, :invalid_study_spec}

  defp expected_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp expected_positive_integer(_value), do: {:error, :invalid_study_spec}

  defp normalize_tier_context(context) do
    context
    |> Enum.reduce_while({:ok, []}, fn
      %{"label" => label, "archive" => archive, "archive_sha256" => digest}, {:ok, acc}
      when is_binary(label) and is_binary(archive) and is_binary(digest) ->
        entry = %{"label" => label, "archive" => archive, "archive_sha256" => digest}

        if Enum.any?(acc, &(&1["label"] == label or &1["archive"] == archive)) do
          {:halt, :error}
        else
          {:cont, {:ok, [entry | acc]}}
        end

      _entry, _acc ->
        {:halt, :error}
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.sort_by(entries, & &1["label"])}
      :error -> :error
    end
  end

  @spec submit(prepared(), mode() | :analyze) :: {:ok, binary()} | {:error, term()}
  def submit(%{bundle: bundle, study_id: study_id}, mode) do
    case service_mode(mode) do
      {:ok, service_mode} -> AnalysisClient.analyze_study(bundle, study_id, service_mode)
      :error -> {:error, :invalid_mode}
    end
  end

  def submit(_prepared, _mode), do: {:error, :invalid_mode}

  @spec parse_result(binary()) :: {:ok, map()} | {:error, term()}
  def parse_result(archive) when is_binary(archive),
    do: AnalysisResult.parse(archive, AnalysisLimits.max_zip_bytes())

  @doc """
  Reports Pilot eligibility from the parsed result.

  An eligible Pilot has a recommendation with both sample counts, is not
  insufficient, and has no non-informative comparison. Final mode has no
  eligibility value.
  """
  @spec pilot_eligible?(mode(), map()) :: boolean() | nil
  def pilot_eligible?(:pilot, analysis), do: pilot_eligibility(analysis) == :eligible
  def pilot_eligible?(_mode, _analysis), do: nil

  @spec pilot_eligibility(map()) :: :eligible | {:ineligible, atom()}
  def pilot_eligibility(%{metadata: metadata}) when is_map(metadata) do
    cond do
      metadata["command_mode"] != "study-pilot" -> {:ineligible, :invalid_pilot_result}
      metadata["insufficient_pilot"] == true -> {:ineligible, :insufficient_pilot}
      non_informative?(metadata) -> {:ineligible, :non_informative_comparison}
      recommendation_eligible?(metadata["recommendation"]) -> :eligible
      true -> {:ineligible, :invalid_recommendation}
    end
  end

  def pilot_eligibility(_analysis), do: {:ineligible, :invalid_pilot_result}

  defp recommendation_eligible?(%{} = recommendation) do
    positive_integer?(recommendation["plan_selection_seed_count"]) and
      positive_integer?(recommendation["attacks_per_plan"]) and
      recommendation["insufficient_pilot"] != true and
      recommendation["non_informative_comparisons"] in [nil, []]
  end

  defp recommendation_eligible?(_recommendation), do: false

  defp non_informative?(metadata), do: metadata["non_informative_comparisons"] not in [nil, []]

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp run_steps(on_phase, prepare_fun, mode) do
    notify(on_phase, :building_bundle)

    with {:ok, prepared} <- prepare_fun.(),
         :ok <- notify(on_phase, :submitting_analysis),
         :ok <- notify(on_phase, :waiting_for_service),
         {:ok, archive} <- submit(prepared, mode) do
      {:ok, {prepared, archive}}
    end
  end

  defp notify(on_phase, phase) when phase in @phases do
    on_phase.(phase)
    :ok
  end

  defp noop_phase(_phase), do: :ok

  defp service_mode(:pilot), do: {:ok, :pilot}
  defp service_mode(:final), do: {:ok, :analyze}
  defp service_mode(:analyze), do: {:ok, :analyze}
  defp service_mode(_mode), do: :error

  defp fetch_specification(specification_id) do
    case StudySpecifications.get(specification_id) do
      %StudySpecification{} = specification -> {:ok, specification}
      nil -> {:error, :specification_not_found}
    end
  end

  defp tier_run_summary(%EvaluationRun{} = run) do
    plan_count = run.resolved_manifest |> PlanPreview.plans() |> length()
    trials = get_in(run.resolved_manifest, ["evaluation", "trials"]) || 0

    %{
      id: run.id,
      manifest_id: manifest_field(run, :manifest_id),
      manifest_title: manifest_field(run, :title),
      graph_title: revision_title(run),
      completed_at: completed_at(run),
      plan_count: plan_count,
      trial_count: plan_count * trials
    }
  end

  defp manifest_field(
         %EvaluationRun{evaluation_manifest: %EvaluationManifest{manifest_id: id}},
         :manifest_id
       ),
       do: id

  defp manifest_field(
         %EvaluationRun{evaluation_manifest: %EvaluationManifest{title: title}},
         :title
       ),
       do: title

  defp manifest_field(_run, _field), do: nil

  defp revision_title(%EvaluationRun{source_graph_revision: %GraphRevision{title: title}}),
    do: title

  defp revision_title(_run), do: nil

  defp completed_at(%EvaluationRun{updated_at: %DateTime{} = updated_at}),
    do: DateTime.to_iso8601(updated_at)

  defp completed_at(_run), do: nil

  # The validator accepts the tuple form and the map form. Normalize both to
  # one canonical tuple form here so every downstream step, including
  # `export_tiers/1`, reads tuples and a validated map cannot raise.
  defp validate_tier_runs(tier_runs) when is_list(tier_runs) do
    case StudyTierValidator.validate(tier_runs) do
      :ok -> {:ok, Enum.map(tier_runs, &normalize_tier_run/1)}
      {:error, :invalid_tier} -> {:error, :invalid_study_tiers}
      {:error, _reason} = error -> StudyTierValidator.normalize(error)
    end
  end

  defp validate_tier_runs(_tier_runs), do: {:error, :no_tiers}

  defp normalize_tier_run({label, run_id}), do: {label, run_id}
  defp normalize_tier_run(%{tier: label, run_id: run_id}), do: {label, run_id}

  # Reuses the authoritative saved-specification validator before any bundle
  # construction. A declaration that omits `tiers` keeps the CLI compatible:
  # the validated tier arguments supply the labels. A declared list stays
  # authoritative and `StudyBundle.archive/2` rejects a list that disagrees
  # with the resolved tiers.
  defp validate_study_spec(study_spec, tier_runs) when is_map(study_spec) do
    study_spec
    |> Map.put_new("tiers", tier_labels(tier_runs))
    |> StudySpecificationContract.validate()
    |> case do
      {:ok, validated} -> {:ok, validated}
      {:error, _errors} -> {:error, :invalid_study_spec}
    end
  end

  defp validate_study_spec(_study_spec, _tier_runs), do: {:error, :invalid_study_spec}

  defp tier_labels(tier_runs), do: Enum.map(tier_runs, &elem(&1, 0))

  defp export_tiers(tier_runs) do
    tier_runs
    |> Enum.reduce_while({:ok, []}, fn {label, run_id}, {:ok, acc} ->
      case export_tier(label, run_id) do
        {:ok, tier} -> {:cont, {:ok, [tier | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tiers} -> {:ok, Enum.reverse(tiers)}
      {:error, _reason} = error -> error
    end
  end

  defp export_tier(label, run_id) do
    case EvaluationRuns.get(run_id) do
      nil ->
        {:error, :not_found}

      %EvaluationRun{purpose: "warmup"} ->
        {:error, :warmup_run}

      %EvaluationRun{status: "completed"} = run ->
        with {:ok, archive, _filename} <- OutputContract.archive(run),
             {:ok, selection_seeds} <- OutputContract.plan_selection_seeds(run) do
          {:ok,
           %{
             tier: label,
             run_id: run_id,
             run: run,
             archive: archive,
             selection_seeds: selection_seeds
           }}
        end

      %EvaluationRun{} ->
        {:error, :incomplete}
    end
  end

  # The prepared tiers already carry their resolved manifests. Reject the whole
  # mapping before bundle construction when one run does not match the derived
  # input shape or when the mapped runs disagree on the model variant or the
  # common analysis settings. The service revalidates the same constraints, so
  # the browser never submits a bundle the loader will refuse.
  defp validate_inputs(tiers, shape, mode) do
    runs = Enum.map(tiers, & &1.run)

    if Enum.all?(
         tiers,
         &StudyInputCompatibility.mode_compatible?(&1.run, shape, mode, &1.selection_seeds)
       ) and StudyInputCompatibility.consistent?(runs, shape, mode) do
      :ok
    else
      {:error, :incompatible_run}
    end
  end

  defp tier_context(tiers) do
    Enum.map(tiers, fn %{tier: label, archive: archive} ->
      %{
        "label" => label,
        "archive" => "tiers/#{label}.zip",
        "archive_sha256" => Base.encode16(:crypto.hash(:sha256, archive), case: :lower)
      }
    end)
  end

  # `:analyze` is the CLI spelling of Final mode. It shares the final seed
  # schedule and the `study-analyze` command mode, so both spellings enforce
  # the same declared schedule.
  defp schedule_mode(:pilot), do: {:ok, :pilot}
  defp schedule_mode(:final), do: {:ok, :final}
  defp schedule_mode(:analyze), do: {:ok, :final}
  defp schedule_mode(_mode), do: {:error, :invalid_mode}
end
