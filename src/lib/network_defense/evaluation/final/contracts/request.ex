defmodule NetworkDefense.Evaluation.Final.Contracts.Request do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  alias NetworkDefense.Evaluation.Final.Contracts.{
    Analysis,
    Assertions,
    FinalError,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.SchemaValidator
  alias NetworkDefense.Evaluation.JsonBoundary
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotResult

  # Root Final analysis request.
  #
  # The request names a pre-created Final snapshot and a completed recommended
  # Pilot. It repeats the declared ordered family, source IDs, copied
  # recommendation counts, explicit analysis settings, one explicit seed per
  # declared comparison, and caller assertions. It never carries an evidence
  # matrix, so the snapshot stays the only owner of Final evidence.
  #
  # No seed is derived here. The caller supplies every Final seed explicitly
  # and separately from the Pilot seeds.

  @request_limit 1_048_576
  @max_issues 50

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          method: String.t(),
          family_id: String.t(),
          study_revision_id: String.t(),
          snapshot_id: String.t(),
          source_pilot_run_id: integer(),
          plan_count: integer(),
          attacks_per_plan: integer(),
          expected_comparisons: [Identity.t()],
          comparison_seeds: [non_neg_integer()],
          analysis: Analysis.t(),
          assertions: Assertions.t()
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    field :method, :string
    field :family_id, :string
    field :study_revision_id, :string
    field :snapshot_id, :string
    field :source_pilot_run_id, :integer
    field :plan_count, :integer
    field :attacks_per_plan, :integer
    field :comparison_seeds, {:array, :integer}
    embeds_many :expected_comparisons, Identity, on_replace: :delete
    embeds_one :analysis, Analysis, on_replace: :update
    embeds_one :assertions, Assertions, on_replace: :update
  end

  def changeset(request, attrs) do
    request
    |> change()
    |> SchemaValidator.matches_schema(attrs, :request)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(term()) :: {:ok, t()} | {:error, FinalError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, encoded} <- encode(attrs),
         :ok <- within_limit(encoded),
         {:ok, request} <- materialize(attrs),
         {:ok, request} <- normalize_uuids(request),
         :ok <- validate_request(request),
         {:ok, canonical_encoded} <- request |> to_params() |> encode(),
         :ok <- within_limit(canonical_encoded) do
      {:ok, request}
    end
  end

  @doc "Correlate one validated request with the stored Final snapshot."
  @spec matches_snapshot(t(), EvidenceSnapshot.t(), SnapshotPayload.t()) ::
          :ok | {:error, FinalError.t()}
  def matches_snapshot(%__MODULE__{} = request, %EvidenceSnapshot{} = snapshot, payload) do
    issues = snapshot_issues(request, snapshot, payload)
    sorted = issues |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)

    case Enum.take(sorted, @max_issues) do
      [] -> :ok
      bounded -> {:error, FinalError.validation_failed(bounded)}
    end
  end

  @doc "Correlate one validated request with the recommended source Pilot result."
  @spec matches_pilot(t(), PilotResult.t()) :: :ok | {:error, FinalError.t()}
  def matches_pilot(%__MODULE__{} = request, %PilotResult{} = pilot) do
    cond do
      pilot.outcome != "recommended" or is_nil(pilot.recommendation) ->
        {:error,
         FinalError.pilot_not_recommended("The source Pilot is not a recommended Pilot result.")}

      pilot.recommendation.plan_count != request.plan_count ->
        {:error,
         FinalError.count_mismatch(
           "The Final plan count does not equal the Pilot recommendation."
         )}

      pilot.recommendation.attacks_per_plan != request.attacks_per_plan ->
        {:error,
         FinalError.count_mismatch(
           "The Final attack count does not equal the Pilot recommendation."
         )}

      true ->
        source_issues(request, pilot)
    end
  end

  defp source_issues(request, pilot) do
    issues =
      [
        {"family_id", request.family_id, pilot.family_id},
        {"study_revision_id", request.study_revision_id, pilot.study_revision_id},
        {"expected_comparisons", Enum.map(request.expected_comparisons, &Identity.key/1),
         Enum.map(pilot.expected_comparisons, &Identity.key/1)}
      ]
      |> Enum.reject(fn {_field, declared, actual} -> declared == actual end)
      |> Enum.map(fn {field, _declared, _actual} ->
        %{
          "code" => "changed_pilot_source",
          "path" => [field],
          "message" => "The Final request must repeat the Pilot study, family, and order.",
          "details" => %{}
        }
      end)

    case issues do
      [] -> :ok
      _issues -> {:error, FinalError.validation_failed(issues)}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs), do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [
      :schema_version,
      :evidence_role,
      :method,
      :family_id,
      :study_revision_id,
      :snapshot_id,
      :source_pilot_run_id,
      :plan_count,
      :attacks_per_plan,
      :comparison_seeds
    ])
    |> cast_embed(:expected_comparisons, required: true)
    |> cast_embed(:analysis, required: true)
    |> cast_embed(:assertions, required: true)
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
           FinalError.workflow_failed("The validated Final request could not be materialized.")
         )}
    end
  end

  defp materialize(_attrs), do: {:error, FinalError.invalid_json_value([])}

  defp string_keys_only(attrs),
    do: JsonBoundary.string_keys_only(attrs, [], &FinalError.invalid_json_value/1)

  defp encode(value), do: JsonBoundary.encode(value, &FinalError.invalid_json_value/1)

  defp within_limit(encoded),
    do: JsonBoundary.within_limit(encoded, @request_limit, &FinalError.request_too_large/1)

  defp normalize_uuids(%__MODULE__{} = request) do
    with {:ok, study_revision_id} <- cast_uuid(request.study_revision_id, "study_revision_id"),
         {:ok, snapshot_id} <- cast_uuid(request.snapshot_id, "snapshot_id") do
      {:ok, %{request | study_revision_id: study_revision_id, snapshot_id: snapshot_id}}
    end
  end

  defp cast_uuid(value, field) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, FinalError.invalid_identifier([field])}
    end
  end

  defp validate_request(%__MODULE__{} = request) do
    issues =
      (duplicate_identity_issues(request.expected_comparisons) ++
         seed_issues(request) ++
         assertion_issues(request.assertions))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, FinalError.validation_failed(issues)}
    end
  end

  defp assertion_issues(%Assertions{} = assertions) do
    case Assertions.issues(assertions) do
      :ok -> []
      issues -> issues
    end
  end

  defp duplicate_identity_issues(identities) do
    {_seen, issues} =
      identities
      |> Enum.with_index()
      |> Enum.reduce({MapSet.new(), []}, fn {identity, index}, {seen, issues} ->
        key = Identity.key(identity)

        if MapSet.member?(seen, key) do
          {seen,
           [
             issue(
               "duplicate_expected_identity",
               ["expected_comparisons", index],
               "Expected comparison identities must be unique.",
               %{"tier" => identity.tier, "budget" => identity.budget}
             )
             | issues
           ]}
        else
          {MapSet.put(seen, key), issues}
        end
      end)

    Enum.reverse(issues)
  end

  # One explicit seed per declared comparison, in declared order. The count
  # check prevents a missing or extra seed from shifting every later stream. The
  # request schema already requires a non-negative integer for every seed, so
  # only the count relation remains here.
  defp seed_issues(%__MODULE__{} = request) do
    declared = length(request.expected_comparisons)
    supplied = length(request.comparison_seeds)

    if declared == supplied do
      []
    else
      [
        issue(
          "seed_count_mismatch",
          ["comparison_seeds"],
          "Every declared comparison must supply exactly one explicit Final seed.",
          %{"declared" => declared, "supplied" => supplied}
        )
      ]
    end
  end

  defp snapshot_issues(%__MODULE__{} = request, snapshot, payload) do
    metadata_issues(request, snapshot) ++
      payload_issues(request, payload) ++
      identity_issues(request, payload) ++
      count_issues(request, payload)
  end

  defp payload_issues(%__MODULE__{} = request, %SnapshotPayload{} = payload) do
    scalar_issues([
      {"schema_version", payload.schema_version, request.schema_version},
      {"evidence_role", payload.evidence_role, request.evidence_role}
    ])
  end

  defp payload_issues(_request, _payload), do: []

  defp metadata_issues(%__MODULE__{} = request, %EvidenceSnapshot{} = snapshot) do
    phase_issues(snapshot) ++
      scalar_issues([
        {"family_id", snapshot.family_id, request.family_id},
        {"study_revision_id", cast_study(snapshot.study_revision_id), request.study_revision_id},
        {"snapshot_id", cast_study(snapshot.id), request.snapshot_id},
        {"schema_version", snapshot.schema_version, request.schema_version}
      ])
  end

  defp phase_issues(%EvidenceSnapshot{} = snapshot) do
    if snapshot.phase == :final do
      []
    else
      [
        issue(
          "snapshot_phase_mismatch",
          ["snapshot_id"],
          "The Final request analyzes Final evidence snapshots only.",
          %{"phase" => to_string(snapshot.phase)}
        )
      ]
    end
  end

  defp scalar_issues(pairs) do
    pairs
    |> Enum.reject(fn {_field, actual, expected} -> actual == expected end)
    |> Enum.map(fn {field, _actual, _expected} ->
      issue(
        "changed_snapshot",
        [field],
        "The stored Final snapshot does not match the Final request.",
        %{}
      )
    end)
  end

  defp cast_study(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp identity_issues(%__MODULE__{} = request, %SnapshotPayload{} = payload) do
    declared = request.expected_comparisons
    stored = Enum.map(payload.comparisons, & &1.identity)
    declared_keys = Enum.map(declared, &Identity.key/1)
    stored_keys = Enum.map(stored, &Identity.key/1)
    declared_set = MapSet.new(declared_keys)
    stored_set = MapSet.new(stored_keys)

    ordered_issues =
      if declared_keys == stored_keys do
        []
      else
        missing_issues(declared, stored_set) ++ unexpected_issues(stored, declared_set)
      end

    reorder_issues =
      if declared_keys != stored_keys and declared_set == stored_set do
        [
          issue(
            "changed_snapshot",
            ["expected_comparisons"],
            "The stored comparison order differs from the declared order.",
            %{}
          )
        ]
      else
        []
      end

    ordered_issues ++ reorder_issues
  end

  defp missing_issues(declared, stored_set) do
    declared
    |> Enum.with_index()
    |> Enum.reject(fn {identity, _index} ->
      MapSet.member?(stored_set, Identity.key(identity))
    end)
    |> Enum.map(fn {identity, index} ->
      issue(
        "missing_comparison",
        ["expected_comparisons", index],
        "Every declared comparison must exist in the Final snapshot.",
        %{"tier" => identity.tier, "budget" => identity.budget}
      )
    end)
  end

  defp unexpected_issues(stored, declared_set) do
    stored
    |> Enum.with_index()
    |> Enum.reject(fn {identity, _index} ->
      MapSet.member?(declared_set, Identity.key(identity))
    end)
    |> Enum.map(fn {identity, index} ->
      issue(
        "unexpected_comparison",
        ["snapshot", "payload", "comparisons", index, "identity"],
        "Every stored comparison must be declared.",
        %{"tier" => identity.tier, "budget" => identity.budget}
      )
    end)
  end

  # The snapshot must hold exactly the selected Pilot sample size: one plan row
  # per side and one shared attack column per selected attack. A different size
  # would analyze a different sample than the one the request labels.
  defp count_issues(%__MODULE__{} = request, %SnapshotPayload{} = payload) do
    payload.comparisons
    |> Enum.with_index()
    |> Enum.flat_map(fn {comparison, index} ->
      comparison_count_issues(comparison, index, request)
    end)
  end

  defp comparison_count_issues(comparison, index, request) do
    evidence = comparison.evidence
    attack_count = length(evidence.attack_seeds)
    path = ["snapshot", "payload", "comparisons", index, "evidence"]

    plan_issues =
      [
        {"alternative", length(evidence.alternative.plans)},
        {"reference", length(evidence.reference.plans)}
      ]
      |> Enum.reject(fn {_side, count} -> count == request.plan_count end)
      |> Enum.map(fn {side, count} ->
        issue(
          "plan_count_mismatch",
          path ++ [side, "plans"],
          "Every Final comparison side must hold the Pilot plan count.",
          %{"expected" => request.plan_count, "actual" => count}
        )
      end)

    attack_issues =
      if attack_count == request.attacks_per_plan do
        []
      else
        [
          issue(
            "attack_count_mismatch",
            path ++ ["attack_seeds"],
            "Every Final comparison must hold the Pilot attack count.",
            %{"expected" => request.attacks_per_plan, "actual" => attack_count}
          )
        ]
      end

    plan_issues ++ attack_issues
  end

  defp issue(code, path, message, details) do
    %{"code" => code, "path" => path, "message" => message, "details" => details}
  end

  defp path_sort_key(path) do
    Enum.map(path, fn
      value when is_binary(value) -> {0, value}
      value when is_integer(value) -> {1, value}
    end)
  end
end
