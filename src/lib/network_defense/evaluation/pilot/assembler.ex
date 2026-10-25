defmodule NetworkDefense.Evaluation.Pilot.Assembler do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonResult,
    CandidateResultRow,
    CandidateSummary,
    PilotError,
    PilotRequest,
    PilotResult,
    Recommendation,
    SnapshotPayload
  }

  # Pure result assembly.
  #
  # Internal candidate positions restore declared order. The persisted result
  # contains candidate IDs and counts only.

  @spec assemble(PilotRequest.t(), SnapshotPayload.t(), [CandidateComparisonResult.t()]) ::
          {:ok, PilotResult.t()} | {:error, PilotError.t()}
  def assemble(%PilotRequest{} = request, %SnapshotPayload{} = payload, results)
      when is_list(results) do
    with :ok <- complete?(request, results) do
      sorted = Enum.sort_by(results, &{&1.candidate_position, &1.comparison_position})
      rows = Enum.map(sorted, &row/1)
      summaries = summaries(request, payload, rows)
      recommendation = recommendation(summaries)

      {outcome, reason} =
        case recommendation do
          nil -> {"insufficient", "no_passing_candidate"}
          _recommendation -> {"recommended", nil}
        end

      result = %PilotResult{
        schema_version: 1,
        evidence_role: request.evidence_role,
        method: request.method,
        pilot_id: request.pilot_id,
        study_revision_id: request.study_revision_id,
        family_id: request.family_id,
        snapshot_id: request.snapshot_id,
        outcome: outcome,
        expected_comparisons: request.expected_comparisons,
        candidates: request.candidates,
        pilot_sampling: request.pilot_sampling,
        precision: request.precision,
        selection: request.selection,
        candidate_results: rows,
        candidate_summaries: summaries,
        recommendation: recommendation,
        insufficient_reason: reason
      }

      PilotResult.parse(PilotResult.to_params(result), request, payload)
    end
  end

  def assemble(_request, _payload, _results),
    do: {:error, PilotError.incomplete_pilot("The pilot result inputs are malformed.")}

  defp complete?(%PilotRequest{} = request, results) do
    expected = length(request.candidates) * length(request.expected_comparisons)

    if length(results) == expected do
      :ok
    else
      {:error,
       PilotError.incomplete_pilot(
         "The candidate result count does not equal the declared pilot size."
       )}
    end
  end

  defp row(%CandidateComparisonResult{} = result) do
    %CandidateResultRow{
      candidate_id: result.candidate.id,
      comparison_position: result.comparison_position,
      plan_count: result.candidate.plan_count,
      attacks_per_plan: result.candidate.attacks_per_plan,
      guarded_half_width: result.guarded_half_width,
      informative: result.informative,
      passes: result.passes
    }
  end

  defp summaries(%PilotRequest{} = request, %SnapshotPayload{} = payload, rows) do
    for candidate <- request.candidates do
      candidate_rows = Enum.filter(rows, &(&1.candidate_id == candidate.id))

      %CandidateSummary{
        candidate_id: candidate.id,
        plan_count: candidate.plan_count,
        attacks_per_plan: candidate.attacks_per_plan,
        worst_guarded_half_width:
          candidate_rows |> Enum.map(& &1.guarded_half_width) |> Enum.max(fn -> 0.0 end),
        all_comparisons_informative: Enum.all?(candidate_rows, & &1.informative),
        non_informative_comparison_positions:
          candidate_rows
          |> Enum.reject(& &1.informative)
          |> Enum.map(& &1.comparison_position)
          |> Enum.sort(),
        all_comparisons_passed: Enum.all?(candidate_rows, & &1.passes),
        predicted_runtime_ms:
          PilotResult.predicted_runtime(payload, candidate.plan_count, candidate.attacks_per_plan)
      }
    end
  end

  @spec recommendation([CandidateSummary.t()]) :: Recommendation.t() | nil
  def recommendation(summaries) do
    summaries
    |> Enum.with_index()
    |> Enum.filter(fn {summary, _position} -> summary.all_comparisons_passed end)
    |> Enum.sort_by(fn {summary, position} -> PilotResult.selection_key(summary, position) end)
    |> List.first()
    |> case do
      nil ->
        nil

      {summary, _position} ->
        %Recommendation{
          candidate_id: summary.candidate_id,
          plan_count: summary.plan_count,
          attacks_per_plan: summary.attacks_per_plan
        }
    end
  end
end
