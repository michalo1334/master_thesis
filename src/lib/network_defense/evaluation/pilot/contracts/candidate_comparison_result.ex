defmodule NetworkDefense.Evaluation.Pilot.Contracts.CandidateComparisonResult do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  import NetworkDefense.Evaluation.ContractSupport

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    Candidate,
    CandidateComparisonRequest,
    PilotError
  }

  alias NetworkDefense.Evaluation.Pilot.SchemaValidator

  # Compact candidate comparison result.
  #
  # It repeats every immutable and scientific input. The parser rejects a
  # response whose echo, decision, or derived pass flag disagrees with the
  # request that produced it.

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
          outer_subsamples: pos_integer(),
          stream_seed: non_neg_integer(),
          guard_quantile: float(),
          target_half_width: float(),
          confidence_level: float(),
          bootstrap_replicates: pos_integer(),
          guarded_half_width: float(),
          informative: boolean(),
          passes: boolean()
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
    field :guarded_half_width, :float
    field :informative, :boolean
    field :passes, :boolean
    embeds_one :identity, Identity, on_replace: :update
    embeds_one :candidate, Candidate, on_replace: :update
  end

  def changeset(result, attrs) do
    result
    |> change()
    |> SchemaValidator.matches_schema(attrs, :candidate_response)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(term(), CandidateComparisonRequest.t()) ::
          {:ok, t()} | {:error, PilotError.t()}
  def parse(attrs, %CandidateComparisonRequest{} = request) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, result} ->
        validate_relations(result, request)

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           PilotError.invalid_response_contract(
             "The candidate comparison response could not be materialized."
           )
         )}
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
      :bootstrap_replicates,
      :guarded_half_width,
      :informative,
      :passes
    ])
    |> cast_embed(:identity, required: true)
    |> cast_embed(:candidate, required: true)
  end

  # A stored mapped row is a strict projection of one response. The request
  # supplies the echoed metadata, so the same relation checks run at fan-in.
  @row_keys ~w(candidate_position candidate_id comparison_position plan_count attacks_per_plan
               guarded_half_width informative passes)

  @spec parse_row(term(), CandidateComparisonRequest.t()) ::
          {:ok, t()} | {:error, PilotError.t()}
  def parse_row(attrs, %CandidateComparisonRequest{} = request) when is_map(attrs) do
    if Enum.sort(Map.keys(attrs)) == Enum.sort(@row_keys) do
      attrs
      |> row_response(request)
      |> parse(request)
    else
      {:error, PilotError.invalid_result("A stored candidate row has an invalid shape.")}
    end
  end

  def parse_row(_attrs, %CandidateComparisonRequest{}),
    do: {:error, PilotError.invalid_result("A stored candidate row is not a JSON object.")}

  defp row_response(attrs, %CandidateComparisonRequest{} = request) do
    %{
      "schema_version" => request.schema_version,
      "method" => request.method,
      "pilot_id" => request.pilot_id,
      "study_revision_id" => request.study_revision_id,
      "family_id" => request.family_id,
      "snapshot_id" => request.snapshot_id,
      "candidate_position" => attrs["candidate_position"],
      "comparison_position" => attrs["comparison_position"],
      "identity" => Identity.to_params(request.identity),
      "candidate" => %{
        "id" => attrs["candidate_id"],
        "plan_count" => attrs["plan_count"],
        "attacks_per_plan" => attrs["attacks_per_plan"]
      },
      "outer_subsamples" => request.outer_subsamples,
      "stream_seed" => request.stream_seed,
      "guard_quantile" => request.guard_quantile,
      "target_half_width" => request.target_half_width,
      "confidence_level" => request.confidence_level,
      "bootstrap_replicates" => request.bootstrap_replicates,
      "guarded_half_width" => attrs["guarded_half_width"],
      "informative" => attrs["informative"],
      "passes" => attrs["passes"]
    }
  end

  defp validate_relations(%__MODULE__{} = result, %CandidateComparisonRequest{} = request) do
    issues =
      (echo_issues(result, request) ++ decision_issues(result))
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(50)

    case issues do
      [] -> {:ok, result}
      _issues -> {:error, PilotError.validation_failed(issues)}
    end
  end

  defp echo_issues(%__MODULE__{} = result, %CandidateComparisonRequest{} = request) do
    scalar_pairs = [
      {"schema_version", result.schema_version, request.schema_version},
      {"method", result.method, request.method},
      {"pilot_id", result.pilot_id, request.pilot_id},
      {"study_revision_id", result.study_revision_id, request.study_revision_id},
      {"family_id", result.family_id, request.family_id},
      {"snapshot_id", result.snapshot_id, request.snapshot_id},
      {"candidate_position", result.candidate_position, request.candidate_position},
      {"comparison_position", result.comparison_position, request.comparison_position},
      {"outer_subsamples", result.outer_subsamples, request.outer_subsamples},
      {"stream_seed", result.stream_seed, request.stream_seed},
      {"guard_quantile", result.guard_quantile, request.guard_quantile},
      {"target_half_width", result.target_half_width, request.target_half_width},
      {"confidence_level", result.confidence_level, request.confidence_level},
      {"bootstrap_replicates", result.bootstrap_replicates, request.bootstrap_replicates}
    ]

    identity_issues =
      if Identity.matches?(result.identity, request.identity) do
        []
      else
        [issue("identity_mismatch", ["identity"], "The response identity changed.")]
      end

    candidate_issues =
      if result.candidate.id == request.candidate.id and
           result.candidate.plan_count == request.candidate.plan_count and
           result.candidate.attacks_per_plan == request.candidate.attacks_per_plan do
        []
      else
        [issue("changed_candidate_result", ["candidate"], "The response candidate changed.")]
      end

    scalar_pairs
    |> Enum.reject(fn {_field, result_value, request_value} -> result_value == request_value end)
    |> Enum.map(fn {field, result_value, request_value} ->
      issue("changed_candidate_result", [field], "The response echo changed.", %{
        "result" => result_value,
        "request" => request_value
      })
    end)
    |> Kernel.++(identity_issues ++ candidate_issues)
  end

  defp decision_issues(%__MODULE__{} = result) do
    expected = result.informative and result.guarded_half_width <= result.target_half_width

    if result.passes == expected do
      []
    else
      [
        issue(
          "invalid_candidate_result",
          ["passes"],
          "The pass flag must equal the declared decision rule."
        )
      ]
    end
  end
end
