defmodule NetworkDefense.Evaluation.Pilot.Contracts.PilotResult do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  import NetworkDefense.Evaluation.ContractSupport

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    Candidate,
    CandidateResultRow,
    CandidateSummary,
    PilotError,
    PilotRequest,
    PilotSampling,
    Precision,
    Recommendation,
    Selection,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Pilot.SchemaValidator

  # Persisted compact Precision Pilot result.
  #
  # It repeats immutable IDs and every candidate and comparison row. It never
  # repeats an evidence matrix or the internal declared candidate position.
  # Read-back recomputes every aggregate from stored rows and runtime evidence.

  @max_issues 50

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          method: String.t(),
          pilot_id: String.t(),
          study_revision_id: String.t(),
          family_id: String.t(),
          snapshot_id: String.t(),
          outcome: String.t(),
          expected_comparisons: [Identity.t()],
          candidates: [Candidate.t()],
          pilot_sampling: PilotSampling.t(),
          precision: Precision.t(),
          selection: Selection.t(),
          candidate_results: [CandidateResultRow.t()],
          candidate_summaries: [CandidateSummary.t()],
          recommendation: Recommendation.t() | nil,
          insufficient_reason: String.t() | nil
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    field :method, :string
    field :pilot_id, :string
    field :study_revision_id, :string
    field :family_id, :string
    field :snapshot_id, :string
    field :outcome, :string
    field :insufficient_reason, :string
    embeds_many :expected_comparisons, Identity, on_replace: :delete
    embeds_many :candidates, Candidate, on_replace: :delete
    embeds_one :pilot_sampling, PilotSampling, on_replace: :update
    embeds_one :precision, Precision, on_replace: :update
    embeds_one :selection, Selection, on_replace: :update
    embeds_many :candidate_results, CandidateResultRow, on_replace: :delete
    embeds_many :candidate_summaries, CandidateSummary, on_replace: :delete
    embeds_one :recommendation, Recommendation, on_replace: :update
  end

  def changeset(result, attrs) do
    result
    |> change()
    |> SchemaValidator.matches_schema(attrs, :result)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(term(), PilotRequest.t(), SnapshotPayload.t()) ::
          {:ok, t()} | {:error, PilotError.t()}
  def parse(attrs, %PilotRequest{} = request, %SnapshotPayload{} = payload) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, result} ->
        validate_relations(result, request, payload)

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           PilotError.invalid_result("The stored pilot result could not be materialized.")
         )}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs), do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [
      :schema_version,
      :evidence_role,
      :method,
      :pilot_id,
      :study_revision_id,
      :family_id,
      :snapshot_id,
      :outcome,
      :insufficient_reason
    ])
    |> cast_embed(:expected_comparisons, required: true)
    |> cast_embed(:candidates, required: true)
    |> cast_embed(:pilot_sampling, required: true)
    |> cast_embed(:precision, required: true)
    |> cast_embed(:selection, required: true)
    |> cast_embed(:candidate_results, required: true)
    |> cast_embed(:candidate_summaries, required: true)
    |> cast_embed(:recommendation)
  end

  defp validate_relations(%__MODULE__{} = result, request, payload) do
    issues =
      (echo_issues(result, request) ++
         row_issues(result, request) ++
         summary_issues(result, request, payload) ++
         outcome_issues(result))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> {:ok, result}
      _issues -> {:error, PilotError.validation_failed(issues)}
    end
  end

  defp echo_issues(%__MODULE__{} = result, %PilotRequest{} = request) do
    scalar_pairs = [
      {"schema_version", result.schema_version, request.schema_version},
      {"evidence_role", result.evidence_role, request.evidence_role},
      {"method", result.method, request.method},
      {"pilot_id", result.pilot_id, request.pilot_id},
      {"study_revision_id", result.study_revision_id, request.study_revision_id},
      {"family_id", result.family_id, request.family_id},
      {"snapshot_id", result.snapshot_id, request.snapshot_id},
      {"pilot_sampling.outer_subsamples", result.pilot_sampling.outer_subsamples,
       request.pilot_sampling.outer_subsamples},
      {"pilot_sampling.seed", result.pilot_sampling.seed, request.pilot_sampling.seed},
      {"precision.target_half_width", result.precision.target_half_width,
       request.precision.target_half_width},
      {"precision.guard_quantile", result.precision.guard_quantile,
       request.precision.guard_quantile},
      {"precision.confidence_level", result.precision.confidence_level,
       request.precision.confidence_level},
      {"precision.bootstrap_replicates", result.precision.bootstrap_replicates,
       request.precision.bootstrap_replicates},
      {"selection.rule", result.selection.rule, request.selection.rule}
    ]

    scalar_issues =
      scalar_pairs
      |> Enum.reject(fn {_path, result_value, request_value} -> result_value == request_value end)
      |> Enum.map(fn {path, result_value, request_value} ->
        issue("changed_candidate_result", String.split(path, "."), "The stored echo changed.", %{
          "result" => result_value,
          "request" => request_value
        })
      end)

    identity_issues =
      if Enum.map(result.expected_comparisons, &Identity.key/1) ==
           Enum.map(request.expected_comparisons, &Identity.key/1) do
        []
      else
        [
          issue(
            "changed_candidate_result",
            ["expected_comparisons"],
            "The stored comparison declaration changed."
          )
        ]
      end

    candidate_issues =
      if Enum.map(result.candidates, &Candidate.to_params/1) ==
           Enum.map(request.candidates, &Candidate.to_params/1) do
        []
      else
        [
          issue(
            "changed_candidate_result",
            ["candidates"],
            "The stored candidate declaration changed."
          )
        ]
      end

    scalar_issues ++ identity_issues ++ candidate_issues
  end

  defp row_issues(%__MODULE__{} = result, %PilotRequest{} = request) do
    comparison_count = length(result.expected_comparisons)
    expected = expected_positions(request.candidates, comparison_count)
    actual = Enum.map(result.candidate_results, &{&1.candidate_id, &1.comparison_position})

    coverage_issues(expected, actual) ++
      duplicate_issues(actual) ++
      order_issues(expected, actual) ++
      content_issues(
        result.candidate_results,
        request.candidates,
        result.precision.target_half_width
      )
  end

  defp expected_positions(candidates, comparison_count) do
    for %Candidate{id: candidate_id} <- candidates,
        comparison_position <- 0..(comparison_count - 1) do
      {candidate_id, comparison_position}
    end
  end

  defp coverage_issues(expected, actual) do
    missing = expected -- actual
    unexpected = actual -- expected

    Enum.map(missing, fn {candidate_id, comparison_position} ->
      issue(
        "incomplete_pilot",
        ["candidate_results"],
        "A declared candidate comparison row is missing.",
        %{"candidate_id" => candidate_id, "comparison_position" => comparison_position}
      )
    end) ++
      Enum.map(unexpected, fn {candidate_id, comparison_position} ->
        issue(
          "unexpected_candidate_result",
          ["candidate_results"],
          "A candidate comparison row was not declared.",
          %{"candidate_id" => candidate_id, "comparison_position" => comparison_position}
        )
      end)
  end

  defp order_issues(expected, actual) do
    if actual != expected and Enum.sort(actual) == Enum.sort(expected) do
      [
        issue(
          "changed_candidate_result",
          ["candidate_results"],
          "Candidate rows must follow the declared candidate and comparison order."
        )
      ]
    else
      []
    end
  end

  defp duplicate_issues(positions) do
    positions
    |> Enum.frequencies()
    |> Enum.filter(fn {_position, count} -> count > 1 end)
    |> Enum.map(fn {{candidate_id, comparison_position}, count} ->
      issue(
        "duplicate_candidate_result",
        ["candidate_results"],
        "A candidate comparison row appears more than once.",
        %{
          "candidate_id" => candidate_id,
          "comparison_position" => comparison_position,
          "count" => count
        }
      )
    end)
  end

  defp content_issues(rows, candidates, target) do
    candidate_map = Map.new(candidates, &{&1.id, &1})

    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {%CandidateResultRow{} = row, index} ->
      content_issue(row, index, candidate_map, target)
    end)
  end

  defp content_issue(%CandidateResultRow{} = row, index, candidate_map, target) do
    path = ["candidate_results", index]

    case Map.get(candidate_map, row.candidate_id) do
      nil ->
        [issue("unexpected_candidate_result", path, "The candidate ID is not declared.")]

      candidate ->
        candidate_size_issue(row, candidate, path) ++ candidate_decision_issue(row, target, path)
    end
  end

  defp candidate_size_issue(%CandidateResultRow{} = row, %Candidate{} = candidate, path) do
    if row.plan_count == candidate.plan_count and
         row.attacks_per_plan == candidate.attacks_per_plan do
      []
    else
      [
        issue(
          "changed_candidate_result",
          path,
          "A candidate row does not repeat its declared candidate size.",
          %{
            "expected_plan_count" => candidate.plan_count,
            "expected_attacks_per_plan" => candidate.attacks_per_plan
          }
        )
      ]
    end
  end

  defp candidate_decision_issue(%CandidateResultRow{} = row, target, path) do
    if row.passes == (row.informative and row.guarded_half_width <= target) do
      []
    else
      [
        issue(
          "invalid_candidate_result",
          path ++ ["passes"],
          "A candidate row pass flag does not follow the declared decision rule."
        )
      ]
    end
  end

  defp summary_issues(
         %__MODULE__{} = result,
         %PilotRequest{} = request,
         %SnapshotPayload{} = payload
       ) do
    candidates = request.candidates

    coverage =
      if length(result.candidate_summaries) == length(candidates) do
        []
      else
        [
          issue(
            "incomplete_pilot",
            ["candidate_summaries"],
            "Every candidate must have exactly one summary."
          )
        ]
      end

    coverage ++ combined_summary_issues(result, payload, candidates)
  end

  defp combined_summary_issues(result, payload, candidates) do
    result.candidate_summaries
    |> Enum.with_index()
    |> Enum.flat_map(fn {summary, index} ->
      summary_issues_for_candidate(
        result,
        payload,
        summary,
        index,
        Enum.at(candidates, index)
      )
    end)
  end

  defp summary_issues_for_candidate(_result, _payload, _summary, index, nil) do
    [
      issue(
        "unexpected_candidate_result",
        ["candidate_summaries", index],
        "A candidate summary was not declared."
      )
    ]
  end

  defp summary_issues_for_candidate(result, payload, summary, index, %Candidate{} = candidate) do
    summary_position_issue(summary, candidate, index) ++
      summary_size_issue(summary, candidate, index) ++
      recomputed_issues(result, payload, summary, index)
  end

  defp summary_position_issue(summary, candidate, index) do
    if summary.candidate_id == candidate.id do
      []
    else
      [
        issue(
          "changed_candidate_result",
          ["candidate_summaries", index, "candidate_id"],
          "Candidate summaries must follow the declared candidate order."
        )
      ]
    end
  end

  defp summary_size_issue(summary, candidate, index) do
    if summary.plan_count == candidate.plan_count and
         summary.attacks_per_plan == candidate.attacks_per_plan do
      []
    else
      [
        issue(
          "changed_candidate_result",
          ["candidate_summaries", index],
          "A candidate summary does not repeat its declared candidate size."
        )
      ]
    end
  end

  defp recomputed_issues(result, payload, summary, index) do
    rows = candidate_rows(result, summary.candidate_id)

    if rows == [] do
      [
        issue(
          "incomplete_pilot",
          ["candidate_summaries", index],
          "A candidate summary has no stored comparison rows."
        )
      ]
    else
      recomputed_row_issues(payload, summary, index, rows)
    end
  end

  defp recomputed_row_issues(payload, summary, index, rows) do
    widths = Enum.map(rows, & &1.guarded_half_width)
    expected_informative = Enum.all?(rows, & &1.informative)

    expected_non_informative =
      rows
      |> Enum.reject(& &1.informative)
      |> Enum.map(& &1.comparison_position)
      |> Enum.sort()

    expected_passed = Enum.all?(rows, & &1.passes)
    expected_runtime = predicted_runtime(payload, summary.plan_count, summary.attacks_per_plan)
    path = ["candidate_summaries", index]

    Enum.reject(
      [
        check(
          summary.worst_guarded_half_width == Enum.max(widths),
          path ++ ["worst_guarded_half_width"],
          "The worst guarded half-width does not equal the stored row maximum."
        ),
        check(
          summary.all_comparisons_informative == expected_informative,
          path ++ ["all_comparisons_informative"],
          "The informative summary flag does not equal the stored rows."
        ),
        check(
          summary.non_informative_comparison_positions == expected_non_informative,
          path ++ ["non_informative_comparison_positions"],
          "The non-informative positions do not equal the stored rows."
        ),
        check(
          summary.all_comparisons_passed == expected_passed,
          path ++ ["all_comparisons_passed"],
          "The passing summary flag does not equal the stored rows."
        ),
        check(
          summary.predicted_runtime_ms == expected_runtime,
          path ++ ["predicted_runtime_ms"],
          "The predicted runtime does not equal the declared runtime evidence."
        )
      ],
      &is_nil/1
    )
  end

  defp check(true, _path, _message), do: nil
  defp check(false, path, message), do: issue("changed_candidate_result", path, message)

  defp candidate_rows(%__MODULE__{} = result, candidate_id) do
    Enum.filter(result.candidate_results, &(&1.candidate_id == candidate_id))
  end

  @spec predicted_runtime(SnapshotPayload.t(), pos_integer(), pos_integer()) :: float()
  def predicted_runtime(%SnapshotPayload{} = payload, plan_count, attacks_per_plan) do
    evidence = payload.runtime_evidence

    plan_term =
      median(evidence.plan_selection_ms) * evidence.tier_count * evidence.strategy_group_count *
        plan_count

    attack_term =
      median(evidence.attack_trial_ms) * evidence.tier_count * evidence.strategy_group_count *
        plan_count * attacks_per_plan

    plan_term + attack_term
  end

  @spec median([number()]) :: float()
  def median(values) when is_list(values) and values != [] do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 0 do
      (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    else
      Enum.at(sorted, middle) * 1.0
    end
  end

  @doc """
  Selection order for one candidate summary and its declared position.

  The selector and the read-back validator use this exact order: predicted
  runtime, more plans, fewer attacks, then declared candidate position.
  """
  @spec selection_key(CandidateSummary.t(), non_neg_integer()) ::
          {number(), integer(), integer(), non_neg_integer()}
  def selection_key(%CandidateSummary{} = summary, candidate_position) do
    {summary.predicted_runtime_ms, -summary.plan_count, summary.attacks_per_plan,
     candidate_position}
  end

  defp outcome_issues(%__MODULE__{} = result) do
    passing =
      result.candidate_summaries
      |> Enum.with_index()
      |> Enum.filter(fn {summary, _position} -> summary.all_comparisons_passed end)

    computed =
      passing
      |> Enum.sort_by(fn {summary, position} -> selection_key(summary, position) end)
      |> List.first()

    case {result.outcome, result.recommendation, result.insufficient_reason, computed} do
      {"recommended", %Recommendation{} = recommendation, nil, {expected, _position}} ->
        if recommendation.candidate_id == expected.candidate_id and
             recommendation.plan_count == expected.plan_count and
             recommendation.attacks_per_plan == expected.attacks_per_plan do
          []
        else
          [
            issue(
              "invalid_candidate_result",
              ["recommendation"],
              "The recommendation does not equal the declared selection rule."
            )
          ]
        end

      {"insufficient", nil, "no_passing_candidate", nil} ->
        []

      {"recommended", _recommendation, _reason, nil} ->
        [
          issue(
            "invalid_candidate_result",
            ["recommendation"],
            "No candidate passes, so a recommendation is invalid."
          )
        ]

      {"insufficient", _recommendation, _reason, {_summary, _position}} ->
        [
          issue(
            "invalid_candidate_result",
            ["insufficient_reason"],
            "A passing candidate exists, so an insufficient outcome is invalid."
          )
        ]

      _inconsistent ->
        [
          issue(
            "invalid_candidate_result",
            ["outcome"],
            "The outcome, recommendation, and insufficiency reason disagree."
          )
        ]
    end
  end
end
