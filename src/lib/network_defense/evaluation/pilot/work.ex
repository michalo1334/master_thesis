defmodule NetworkDefense.Evaluation.Pilot.Work do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.Evidence
  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    Candidate,
    CandidateComparisonRequest,
    CandidateComparisonResult,
    PilotError,
    PilotRequest,
    SnapshotPayload
  }

  # Canonical mapped work for one validated pilot.
  #
  # Candidate positions follow the declared ordered candidates. Comparison
  # positions follow the declared order.
  #
  # The historical comparison stream is preserved exactly:
  #
  #     stream_seed = base_seed + tier_rank * 1_000_000 + comparison_index * 2
  #
  # `tier_rank` is the first appearance of each distinct tier in the declared
  # comparison list. `comparison_index` is that comparison's occurrence order
  # within its tier. Interleaving therefore never changes either value.

  @tier_stride 1_000_000
  @comparison_stride 2

  @type item :: %{required(String.t()) => term()}

  @spec canonical_items(PilotRequest.t(), SnapshotPayload.t()) ::
          {:ok, [item()]} | {:error, PilotError.t()}
  def canonical_items(%PilotRequest{} = request, %SnapshotPayload{} = payload) do
    candidates = request.candidates
    comparisons = request.expected_comparisons
    ranks = tier_ranks(comparisons)
    indices = comparison_indices(comparisons)

    if length(payload.comparisons) != length(comparisons) do
      {:error, PilotError.changed_snapshot("The snapshot comparison count changed.")}
    else
      comparisons_with_indices = Enum.zip(comparisons, indices)

      items =
        for {candidate, candidate_position} <- Enum.with_index(candidates),
            {{identity, occurrence_index}, comparison_index} <-
              Enum.with_index(comparisons_with_indices) do
          item(
            request,
            identity,
            candidate,
            candidate_position,
            comparison_index,
            Map.fetch!(ranks, identity.tier),
            occurrence_index
          )
        end

      {:ok, items}
    end
  end

  @spec preflight(PilotRequest.t(), SnapshotPayload.t()) :: :ok | {:error, PilotError.t()}
  def preflight(%PilotRequest{} = request, %SnapshotPayload{} = payload) do
    with {:ok, items} <- canonical_items(request, payload) do
      Enum.reduce_while(items, :ok, fn item, :ok -> preflight_item(item, request, payload) end)
    end
  end

  defp preflight_item(item, request, payload) do
    case candidate_request(request, payload, item) do
      {:ok, _candidate_request} -> {:cont, :ok}
      {:error, %PilotError{} = error} -> {:halt, {:error, error}}
    end
  end

  @spec candidate_request(PilotRequest.t(), SnapshotPayload.t(), item()) ::
          {:ok, CandidateComparisonRequest.t()} | {:error, PilotError.t()}
  def candidate_request(%PilotRequest{} = request, %SnapshotPayload{} = payload, item)
      when is_map(item) do
    with {:ok, candidate} <- candidate_at(request, item["candidate_position"]),
         :ok <- candidate_agrees(item, candidate),
         {:ok, comparison} <- comparison_at(payload, item["comparison_position"]),
         :ok <- identity_agrees(item["identity"], comparison.identity) do
      %{
        "schema_version" => 1,
        "method" => "precision_pilot_candidate_v1",
        "pilot_id" => item["pilot_id"],
        "study_revision_id" => item["study_revision_id"],
        "family_id" => item["family_id"],
        "snapshot_id" => item["snapshot_id"],
        "candidate_position" => item["candidate_position"],
        "comparison_position" => item["comparison_position"],
        "identity" => Identity.to_params(comparison.identity),
        "candidate" => %{
          "id" => candidate.id,
          "plan_count" => candidate.plan_count,
          "attacks_per_plan" => candidate.attacks_per_plan
        },
        "evidence" => Evidence.to_params(comparison.evidence),
        "outer_subsamples" => item["outer_subsamples"],
        "stream_seed" => item["stream_seed"],
        "guard_quantile" => item["guard_quantile"],
        "target_half_width" => item["target_half_width"],
        "confidence_level" => item["confidence_level"],
        "bootstrap_replicates" => item["bootstrap_replicates"]
      }
      |> CandidateComparisonRequest.parse()
    end
  end

  def candidate_request(_request, _payload, _item),
    do: {:error, PilotError.incomplete_pilot("A persisted pilot work item is malformed.")}

  defp candidate_at(%PilotRequest{} = request, position)
       when is_integer(position) and position >= 0 do
    case Enum.at(request.candidates, position) do
      %Candidate{} = candidate -> {:ok, candidate}
      nil -> {:error, PilotError.incomplete_pilot("A work item compares a missing candidate.")}
    end
  end

  defp candidate_at(_request, _position),
    do: {:error, PilotError.incomplete_pilot("A work item has no candidate position.")}

  defp candidate_agrees(item, %Candidate{} = candidate) do
    if item["candidate_id"] == candidate.id and
         item["plan_count"] == candidate.plan_count and
         item["attacks_per_plan"] == candidate.attacks_per_plan do
      :ok
    else
      {:error, PilotError.changed_candidate_result("A work item candidate changed.")}
    end
  end

  @spec result_params(CandidateComparisonResult.t()) :: map()
  def result_params(%CandidateComparisonResult{} = result) do
    %{
      "candidate_position" => result.candidate_position,
      "candidate_id" => result.candidate.id,
      "comparison_position" => result.comparison_position,
      "plan_count" => result.candidate.plan_count,
      "attacks_per_plan" => result.candidate.attacks_per_plan,
      "guarded_half_width" => result.guarded_half_width,
      "informative" => result.informative,
      "passes" => result.passes
    }
  end

  @spec stream_seed(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def stream_seed(base_seed, tier_rank, comparison_index) do
    base_seed + tier_rank * @tier_stride + comparison_index * @comparison_stride
  end

  defp item(
         request,
         identity,
         %Candidate{id: candidate_id, plan_count: plan_count, attacks_per_plan: attacks_per_plan},
         candidate_position,
         comparison_position,
         tier_rank,
         occurrence_index
       ) do
    %{
      "pilot_id" => request.pilot_id,
      "study_revision_id" => request.study_revision_id,
      "family_id" => request.family_id,
      "snapshot_id" => request.snapshot_id,
      "candidate_position" => candidate_position,
      "candidate_id" => candidate_id,
      "comparison_position" => comparison_position,
      "plan_count" => plan_count,
      "attacks_per_plan" => attacks_per_plan,
      "identity" => Identity.to_params(identity),
      "outer_subsamples" => request.pilot_sampling.outer_subsamples,
      "stream_seed" => stream_seed(request.pilot_sampling.seed, tier_rank, occurrence_index),
      "guard_quantile" => request.precision.guard_quantile,
      "target_half_width" => request.precision.target_half_width,
      "confidence_level" => request.precision.confidence_level,
      "bootstrap_replicates" => request.precision.bootstrap_replicates
    }
  end

  defp tier_ranks(identities) do
    {ranks, _next} =
      Enum.reduce(identities, {%{}, 0}, fn identity, {ranks, next} ->
        if Map.has_key?(ranks, identity.tier) do
          {ranks, next}
        else
          {Map.put(ranks, identity.tier, next), next + 1}
        end
      end)

    ranks
  end

  defp comparison_indices(identities) do
    identities
    |> Enum.map_reduce(%{}, fn identity, counts ->
      index = Map.get(counts, identity.tier, 0)
      {index, Map.put(counts, identity.tier, index + 1)}
    end)
    |> elem(0)
  end

  defp comparison_at(%SnapshotPayload{} = payload, position) when is_integer(position) do
    case Enum.at(payload.comparisons, position) do
      nil -> {:error, PilotError.incomplete_pilot("A work item compares a missing snapshot row.")}
      comparison -> {:ok, comparison}
    end
  end

  defp comparison_at(_payload, _position),
    do: {:error, PilotError.incomplete_pilot("A work item has no comparison position.")}

  defp identity_agrees(attrs, %Identity{} = identity) do
    case Identity.new(attrs) do
      {:ok, declared} ->
        if Identity.matches?(declared, identity) do
          :ok
        else
          {:error, PilotError.changed_candidate_result("A work item identity changed.")}
        end

      :error ->
        {:error, PilotError.incomplete_pilot("A work item identity is malformed.")}
    end
  end
end
