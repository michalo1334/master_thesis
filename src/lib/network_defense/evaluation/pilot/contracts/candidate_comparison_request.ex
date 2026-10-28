defmodule NetworkDefense.Evaluation.Pilot.Contracts.CandidateComparisonRequest do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  import NetworkDefense.Evaluation.ContractSupport

  alias NetworkDefense.Evaluation.Comparison.Contracts.Evidence
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.JsonBoundary
  alias NetworkDefense.Evaluation.Pilot.Contracts.{Candidate, PilotError}
  alias NetworkDefense.Evaluation.Pilot.{Limits, SchemaValidator}

  # One bounded compute request. It carries one comparison matrix in memory and
  # never enters Gust state.
  #
  # Version 1 uses one method name. The request repeats every scientific value,
  # so the Python result can echo and correlate it without a second input.

  @max_issues 50

  @type t :: %__MODULE__{
          schema_version: integer(),
          method: String.t(),
          pilot_id: String.t(),
          study_revision_id: String.t(),
          family_id: String.t(),
          snapshot_id: String.t(),
          candidate_position: non_neg_integer(),
          comparison_position: non_neg_integer(),
          identity: Identity.t(),
          candidate: Candidate.t(),
          evidence: struct(),
          outer_subsamples: pos_integer(),
          stream_seed: non_neg_integer(),
          guard_quantile: float(),
          target_half_width: float(),
          confidence_level: float(),
          bootstrap_replicates: pos_integer()
        }

  embedded_schema do
    field :schema_version, :integer
    field :method, :string
    field :pilot_id, :string
    field :study_revision_id, :string
    field :family_id, :string
    field :snapshot_id, :string
    field :candidate_position, :integer
    field :comparison_position, :integer
    field :outer_subsamples, :integer
    field :stream_seed, :integer
    field :guard_quantile, :float
    field :target_half_width, :float
    field :confidence_level, :float
    field :bootstrap_replicates, :integer
    embeds_one :identity, Identity, on_replace: :update
    embeds_one :candidate, Candidate, on_replace: :update
    embeds_one :evidence, Evidence, on_replace: :update
  end

  def changeset(request, attrs) do
    request
    |> change()
    |> SchemaValidator.matches_schema(attrs, :candidate_request)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(term()) :: {:ok, t()} | {:error, PilotError.t()}
  def parse(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, request} <- materialize(attrs),
         {:ok, limits} <- Limits.fetch(),
         :ok <- validate_request(request, limits),
         :ok <- within_byte_limit(request, limits) do
      {:ok, request}
    end
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs), do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [
      :schema_version,
      :method,
      :pilot_id,
      :study_revision_id,
      :family_id,
      :snapshot_id,
      :candidate_position,
      :comparison_position,
      :outer_subsamples,
      :stream_seed,
      :guard_quantile,
      :target_half_width,
      :confidence_level,
      :bootstrap_replicates
    ])
    |> cast_embed(:identity, required: true)
    |> cast_embed(:candidate, required: true)
    |> cast_embed(:evidence, required: true)
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
           PilotError.invalid_response_contract(
             "The candidate comparison request could not be materialized."
           )
         )}
    end
  end

  defp materialize(_attrs), do: {:error, PilotError.invalid_json_value([])}

  defp string_keys_only(attrs),
    do: JsonBoundary.string_keys_only(attrs, [], &PilotError.invalid_json_value/1)

  defp within_byte_limit(%__MODULE__{} = request, %Limits{} = limits) do
    with {:ok, bytes} <- encoded_size(request) do
      if bytes <= limits.candidate_request_bytes do
        :ok
      else
        {:error, PilotError.request_too_large(limits.candidate_request_bytes, bytes)}
      end
    end
  end

  defp encoded_size(%__MODULE__{} = request) do
    with {:ok, encoded} <-
           JsonBoundary.encode(to_params(request), &PilotError.invalid_json_value/1) do
      {:ok, IO.iodata_length(encoded)}
    end
  end

  defp validate_request(%__MODULE__{} = request, %Limits{} = limits) do
    issues =
      (identity_issues(request) ++
         bounds_issues(request) ++
         limit_issues(request, limits))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(@max_issues)

    case issues do
      [] -> :ok
      _issues -> {:error, PilotError.validation_failed(issues)}
    end
  end

  defp identity_issues(%__MODULE__{} = request) do
    identity = request.identity
    evidence = request.evidence

    [
      {"alternative", identity.alternative, evidence.alternative.strategy},
      {"reference", identity.reference, evidence.reference.strategy},
      {"outcome", identity.outcome, evidence.outcome}
    ]
    |> Enum.reject(fn {_field, declared, actual} -> declared == actual end)
    |> Enum.map(fn {field, declared, actual} ->
      issue(
        "identity_mismatch",
        ["identity", field],
        "The identity field must agree with the candidate evidence.",
        %{"declared" => declared, "request" => actual}
      )
    end)
  end

  defp bounds_issues(%__MODULE__{} = request) do
    evidence = request.evidence
    candidate = request.candidate
    available_plans = min(length(evidence.alternative.plans), length(evidence.reference.plans))
    available_attacks = length(evidence.attack_seeds)

    plan_issues =
      if candidate.plan_count > available_plans do
        [
          issue(
            "candidate_exceeds_plan_rows",
            ["candidate", "plan_count"],
            "The candidate plan count exceeds the available plan rows.",
            %{"candidate" => candidate.plan_count, "available" => available_plans}
          )
        ]
      else
        []
      end

    attack_issues =
      if candidate.attacks_per_plan > available_attacks do
        [
          issue(
            "candidate_exceeds_attack_columns",
            ["candidate", "attacks_per_plan"],
            "The candidate attack count exceeds the available attack columns.",
            %{"candidate" => candidate.attacks_per_plan, "available" => available_attacks}
          )
        ]
      else
        []
      end

    plan_issues ++ attack_issues
  end

  defp limit_issues(%__MODULE__{} = request, %Limits{} = limits) do
    count_limit_issue(
      request.outer_subsamples > limits.outer_subsamples,
      ["outer_subsamples"],
      "The outer subsample count exceeds the configured limit.",
      limits.outer_subsamples,
      request.outer_subsamples
    ) ++
      count_limit_issue(
        request.bootstrap_replicates > limits.bootstrap_replicates,
        ["bootstrap_replicates"],
        "The bootstrap replicate count exceeds the configured limit.",
        limits.bootstrap_replicates,
        request.bootstrap_replicates
      ) ++
      count_limit_issue(
        request.candidate.plan_count > limits.plans_per_side,
        ["candidate", "plan_count"],
        "The candidate plan count exceeds the configured plan-row limit.",
        limits.plans_per_side,
        request.candidate.plan_count
      ) ++
      count_limit_issue(
        request.candidate.attacks_per_plan > limits.attack_columns,
        ["candidate", "attacks_per_plan"],
        "The candidate attack count exceeds the configured attack-column limit.",
        limits.attack_columns,
        request.candidate.attacks_per_plan
      )
  end

  defp count_limit_issue(false, _path, _message, _limit, _actual), do: []

  defp count_limit_issue(true, path, message, limit, actual) do
    [
      issue("invalid_analysis_setting", path, message, %{
        "limit" => limit,
        "actual" => actual
      })
    ]
  end
end
