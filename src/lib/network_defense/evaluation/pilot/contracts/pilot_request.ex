defmodule NetworkDefense.Evaluation.Pilot.Contracts.PilotRequest do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  import NetworkDefense.Evaluation.ContractSupport

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.ExpectedComparisons
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.JsonBoundary

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    Candidate,
    PilotError,
    PilotSampling,
    Precision,
    Selection,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Pilot.{Limits, SchemaValidator}

  # Root Precision Pilot declaration.
  #
  # Every scientific value is declared by the caller. The declared comparison
  # order is the only source of tier rank and within-tier occurrence order.

  @request_limit 1_048_576
  @max_issues 50

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          method: String.t(),
          pilot_id: String.t(),
          study_revision_id: String.t(),
          family_id: String.t(),
          snapshot_id: String.t(),
          expected_comparisons: [Identity.t()],
          candidates: [Candidate.t()],
          pilot_sampling: PilotSampling.t(),
          precision: Precision.t(),
          selection: Selection.t()
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    field :method, :string
    field :pilot_id, :string
    field :study_revision_id, :string
    field :family_id, :string
    field :snapshot_id, :string
    embeds_many :expected_comparisons, Identity, on_replace: :delete
    embeds_many :candidates, Candidate, on_replace: :delete
    embeds_one :pilot_sampling, PilotSampling, on_replace: :update
    embeds_one :precision, Precision, on_replace: :update
    embeds_one :selection, Selection, on_replace: :update
  end

  def changeset(request, attrs) do
    request
    |> change()
    |> SchemaValidator.matches_schema(attrs, :request)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(term()) :: {:ok, t()} | {:error, PilotError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, encoded} <- encode(attrs),
         :ok <- within_limit(encoded),
         {:ok, request} <- materialize(attrs),
         {:ok, request} <- normalize_uuids(request),
         {:ok, limits} <- Limits.fetch(),
         :ok <- validate_request(request, limits),
         {:ok, canonical_encoded} <- request |> to_params() |> encode(),
         :ok <- within_limit(canonical_encoded) do
      {:ok, request}
    end
  end

  @spec matches_snapshot(t(), EvidenceSnapshot.t(), SnapshotPayload.t()) ::
          :ok | {:error, PilotError.t()}
  def matches_snapshot(%__MODULE__{} = request, %EvidenceSnapshot{} = snapshot, payload) do
    issues =
      (metadata_issues(request, snapshot, payload) ++
         identity_issues(request, payload) ++ bounds_issues(request, payload))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, PilotError.validation_failed(issues)}
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
      :snapshot_id
    ])
    |> cast_embed(:expected_comparisons, required: true)
    |> cast_embed(:candidates, required: true)
    |> cast_embed(:pilot_sampling, required: true)
    |> cast_embed(:precision, required: true)
    |> cast_embed(:selection, required: true)
  end

  defp materialize(attrs) when is_map(attrs) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, request} ->
        {:ok, request}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           PilotError.workflow_failed("The validated pilot request could not be materialized.")
         )}
    end
  end

  defp materialize(_attrs), do: {:error, PilotError.invalid_json_value([])}

  defp string_keys_only(attrs),
    do: JsonBoundary.string_keys_only(attrs, [], &PilotError.invalid_json_value/1)

  defp encode(value), do: JsonBoundary.encode(value, &PilotError.invalid_json_value/1)

  defp within_limit(encoded),
    do: JsonBoundary.within_limit(encoded, @request_limit, &PilotError.request_too_large/1)

  defp normalize_uuids(%__MODULE__{} = request) do
    with {:ok, study_revision_id} <- cast_uuid(request.study_revision_id, "study_revision_id"),
         {:ok, snapshot_id} <- cast_uuid(request.snapshot_id, "snapshot_id") do
      {:ok, %{request | study_revision_id: study_revision_id, snapshot_id: snapshot_id}}
    end
  end

  defp cast_uuid(value, field) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, PilotError.invalid_identifier([field])}
    end
  end

  defp validate_request(%__MODULE__{} = request, %Limits{} = limits) do
    issues =
      (ExpectedComparisons.duplicate_issues(request.expected_comparisons) ++
         duplicate_candidate_issues(request.candidates) ++
         limit_issues(request, limits))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, PilotError.validation_failed(issues)}
    end
  end

  defp duplicate_candidate_issues(candidates) do
    id_issues =
      candidates
      |> Enum.map(& &1.id)
      |> duplicates()
      |> Enum.map(fn id ->
        issue(
          "duplicate_candidate_id",
          ["candidates"],
          "Candidate IDs must be unique.",
          %{"id" => id}
        )
      end)

    pair_issues =
      candidates
      |> Enum.map(&{&1.plan_count, &1.attacks_per_plan})
      |> duplicates()
      |> Enum.map(fn {plan_count, attacks_per_plan} ->
        issue(
          "duplicate_candidate_size",
          ["candidates"],
          "Candidate plan and attack counts must be unique.",
          %{"plan_count" => plan_count, "attacks_per_plan" => attacks_per_plan}
        )
      end)

    id_issues ++ pair_issues
  end

  defp duplicates(values) do
    {duplicates, _seen} =
      Enum.reduce(values, {[], MapSet.new()}, fn value, {duplicates, seen} ->
        if MapSet.member?(seen, value) do
          {[value | duplicates], seen}
        else
          {duplicates, MapSet.put(seen, value)}
        end
      end)

    duplicates |> Enum.reverse() |> Enum.uniq()
  end

  defp limit_issues(%__MODULE__{} = request, %Limits{} = limits) do
    candidates = request.candidates
    comparison_count = length(request.expected_comparisons)
    work_items = length(candidates) * comparison_count
    plan_counts = Enum.map(candidates, & &1.plan_count)
    attack_counts = Enum.map(candidates, & &1.attacks_per_plan)

    count_issue(
      comparison_count > limits.comparison_count,
      ["expected_comparisons"],
      "The declared comparison count exceeds the configured limit.",
      limits.comparison_count,
      comparison_count
    ) ++
      count_issue(
        length(candidates) > limits.candidate_count,
        ["candidates"],
        "The declared candidate count exceeds the configured limit.",
        limits.candidate_count,
        length(candidates)
      ) ++
      value_limit_issues(
        plan_counts,
        "plan_count",
        limits.plans_per_side,
        "A candidate exceeds the configured plan-row limit."
      ) ++
      value_limit_issues(
        attack_counts,
        "attacks_per_plan",
        limits.attack_columns,
        "A candidate exceeds the configured attack-column limit."
      ) ++
      count_issue(
        work_items > limits.work_items,
        ["candidates"],
        "The declared candidate work count exceeds the configured limit.",
        limits.work_items,
        work_items
      ) ++
      count_issue(
        request.pilot_sampling.outer_subsamples > limits.outer_subsamples,
        ["pilot_sampling", "outer_subsamples"],
        "The outer subsample count exceeds the configured limit.",
        limits.outer_subsamples,
        request.pilot_sampling.outer_subsamples
      ) ++
      count_issue(
        request.precision.bootstrap_replicates > limits.bootstrap_replicates,
        ["precision", "bootstrap_replicates"],
        "The bootstrap replicate count exceeds the configured limit.",
        limits.bootstrap_replicates,
        request.precision.bootstrap_replicates
      )
  end

  defp value_limit_issues(values, field, limit, message) do
    values
    |> Enum.with_index()
    |> Enum.reject(fn {value, _index} -> value <= limit end)
    |> Enum.map(fn {value, index} ->
      issue("invalid_analysis_setting", ["candidates", index, field], message, %{
        "limit" => limit,
        "actual" => value
      })
    end)
  end

  defp count_issue(false, _path, _message, _limit, _actual), do: []

  defp count_issue(true, path, message, limit, actual),
    do: [count_limit_issue(path, message, limit, actual)]

  defp count_limit_issue(path, message, limit, actual) do
    issue("invalid_analysis_setting", path, message, %{"limit" => limit, "actual" => actual})
  end

  defp metadata_issues(%__MODULE__{} = request, %EvidenceSnapshot{} = snapshot, payload) do
    phase_issues(snapshot, payload) ++
      revision_issues(request, snapshot) ++
      schema_issues(request, snapshot, payload)
  end

  defp phase_issues(%EvidenceSnapshot{} = snapshot, %SnapshotPayload{} = payload) do
    if snapshot.phase == :pilot and payload.evidence_role == "pilot" do
      []
    else
      [
        issue(
          "snapshot_phase_mismatch",
          ["snapshot_id"],
          "Version 1 analyzes Pilot evidence snapshots only.",
          %{"phase" => to_string(snapshot.phase), "evidence_role" => payload.evidence_role}
        )
      ]
    end
  end

  defp revision_issues(%__MODULE__{} = request, %EvidenceSnapshot{} = snapshot) do
    family_issues =
      if snapshot.family_id == request.family_id do
        []
      else
        [
          issue(
            "changed_snapshot",
            ["family_id"],
            "The snapshot family ID does not match the pilot request.",
            %{"request" => request.family_id, "snapshot" => snapshot.family_id}
          )
        ]
      end

    study_issues =
      case Ecto.UUID.cast(snapshot.study_revision_id) do
        {:ok, study_revision_id} when study_revision_id == request.study_revision_id ->
          []

        _different ->
          [
            issue(
              "changed_snapshot",
              ["study_revision_id"],
              "The snapshot study revision does not match the pilot request.",
              %{}
            )
          ]
      end

    id_issues =
      case Ecto.UUID.cast(snapshot.id) do
        {:ok, snapshot_id} when snapshot_id == request.snapshot_id ->
          []

        _different ->
          [
            issue(
              "changed_snapshot",
              ["snapshot_id"],
              "The stored snapshot ID does not match the pilot request.",
              %{}
            )
          ]
      end

    family_issues ++ study_issues ++ id_issues
  end

  defp schema_issues(%__MODULE__{} = request, %EvidenceSnapshot{} = snapshot, payload) do
    if request.schema_version == snapshot.schema_version and
         payload.schema_version == request.schema_version do
      []
    else
      [
        issue(
          "changed_snapshot",
          ["schema_version"],
          "The snapshot schema version does not match the pilot request.",
          %{"request" => request.schema_version, "snapshot" => snapshot.schema_version}
        )
      ]
    end
  end

  defp identity_issues(%__MODULE__{} = request, %SnapshotPayload{} = payload) do
    ExpectedComparisons.snapshot_issues(
      request.expected_comparisons,
      Enum.map(payload.comparisons, & &1.identity),
      "Every declared comparison must exist in the snapshot."
    )
  end

  defp bounds_issues(%__MODULE__{} = request, %SnapshotPayload{} = payload) do
    max_plans = request.candidates |> Enum.map(& &1.plan_count) |> Enum.max()
    max_attacks = request.candidates |> Enum.map(& &1.attacks_per_plan) |> Enum.max()

    payload.comparisons
    |> Enum.with_index()
    |> Enum.flat_map(fn {comparison, index} ->
      evidence = comparison.evidence
      available_plans = min(length(evidence.alternative.plans), length(evidence.reference.plans))
      available_attacks = length(evidence.attack_seeds)

      plan_issues =
        if max_plans > available_plans do
          [
            issue(
              "candidate_exceeds_plan_rows",
              ["snapshot", "payload", "comparisons", index, "evidence"],
              "A candidate needs more plan rows than the snapshot holds.",
              %{"candidate" => max_plans, "available" => available_plans}
            )
          ]
        else
          []
        end

      attack_issues =
        if max_attacks > available_attacks do
          [
            issue(
              "candidate_exceeds_attack_columns",
              ["snapshot", "payload", "comparisons", index, "evidence", "attack_seeds"],
              "A candidate needs more attack columns than the snapshot holds.",
              %{"candidate" => max_attacks, "available" => available_attacks}
            )
          ]
        else
          []
        end

      plan_issues ++ attack_issues
    end)
  end
end
