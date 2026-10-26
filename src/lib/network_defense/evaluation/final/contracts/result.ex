defmodule NetworkDefense.Evaluation.Final.Contracts.Result do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonRequest, ComparisonStatistics}

  alias NetworkDefense.Evaluation.Family.Contracts.{
    Adjustment,
    HolmResponse,
    Identity,
    ResultComparison
  }

  alias NetworkDefense.Evaluation.Final.Contracts.{Assertions, FinalError, Request}

  alias NetworkDefense.Evaluation.Final.SchemaValidator

  # Persisted Final result.
  #
  # It keeps the per-comparison intervals unchanged, adds one Holm adjustment
  # row per declared identity, and repeats the Final source binding. The
  # caller assertions are carried with an explicit caller-asserted basis.
  #
  # Read-back validates the stored request, comparison, Holm, source, and order
  # relations. It does not recompute a statistic and cannot detect every
  # relation-preserving byte change.

  @type member :: %{
          identity: Identity.t(),
          request: ComparisonRequest.t(),
          statistics: ComparisonStatistics.t()
        }

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          assertion_basis: String.t(),
          family_id: String.t(),
          method: String.t(),
          alpha: float(),
          family_size: integer(),
          study_revision_id: String.t(),
          snapshot_id: String.t(),
          source_pilot_run_id: integer(),
          plan_count: integer(),
          attacks_per_plan: integer(),
          assertions: Assertions.t(),
          comparisons: [ResultComparison.t()]
        }

  embedded_schema do
    field :schema_version, :integer
    field :evidence_role, :string
    field :assertion_basis, :string
    field :family_id, :string
    field :method, :string
    field :alpha, :float
    field :family_size, :integer
    field :study_revision_id, :string
    field :snapshot_id, :string
    field :source_pilot_run_id, :integer
    field :plan_count, :integer
    field :attacks_per_plan, :integer
    embeds_one :assertions, Assertions, on_replace: :update
    embeds_many :comparisons, ResultComparison, on_replace: :delete
  end

  def changeset(result, attrs) do
    result
    |> change()
    |> SchemaValidator.matches_schema(attrs, :result)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(map(), Request.t(), [member()]) :: {:ok, t()} | {:error, FinalError.t()}
  def parse(attrs, %Request{} = request, members) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, result} ->
        validate_relations(result, request, members)

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           FinalError.invalid_result("The stored Final result could not be materialized.")
         )}
    end
  end

  @spec from_response(Request.t(), [member()], HolmResponse.t()) ::
          {:ok, t()} | {:error, FinalError.t()}
  def from_response(%Request{} = request, members, %HolmResponse{} = response) do
    comparisons =
      members
      |> Enum.zip(response.results)
      |> Enum.map(fn {member, adjusted} ->
        %ResultComparison{
          identity: member.identity,
          statistics: member.statistics,
          adjustment: %Adjustment{
            adjusted_p_value: adjusted.adjusted_p_value,
            reject_null: adjusted.reject_null
          }
        }
      end)

    result = %__MODULE__{
      schema_version: 1,
      evidence_role: request.evidence_role,
      assertion_basis: "caller_asserted",
      family_id: request.family_id,
      method: request.method,
      alpha: request.analysis.alpha,
      family_size: length(comparisons),
      study_revision_id: request.study_revision_id,
      snapshot_id: request.snapshot_id,
      source_pilot_run_id: request.source_pilot_run_id,
      plan_count: request.plan_count,
      attacks_per_plan: request.attacks_per_plan,
      assertions: request.assertions,
      comparisons: comparisons
    }

    parse(to_params(result), request, members)
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs), do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [
      :schema_version,
      :evidence_role,
      :assertion_basis,
      :family_id,
      :method,
      :alpha,
      :family_size,
      :study_revision_id,
      :snapshot_id,
      :source_pilot_run_id,
      :plan_count,
      :attacks_per_plan
    ])
    |> cast_embed(:assertions, required: true)
    |> cast_embed(:comparisons, required: true)
  end

  defp validate_relations(%__MODULE__{} = result, %Request{} = request, members) do
    expected = request.expected_comparisons

    with :ok <- check_metadata(result, request, expected),
         :ok <- check_counts(result, expected, members),
         :ok <- validate_intrinsic(result) do
      parse_comparisons(result, result.comparisons, members)
    end
  end

  # Header relations in declared check order. The first failing relation names
  # the mismatch, so the error stays specific.
  defp check_metadata(%__MODULE__{} = result, %Request{} = request, expected) do
    checks = [
      {result.evidence_role == request.evidence_role,
       "The stored Final evidence role does not match the request."},
      {result.assertion_basis == "caller_asserted",
       "The stored Final assertions must keep their caller-asserted basis."},
      {result.family_id == request.family_id,
       "The stored Final family ID does not match the request."},
      {result.method == request.method,
       "The stored Final correction method does not match the request."},
      {result.alpha == request.analysis.alpha,
       "The stored Final alpha does not match the request."},
      {result.family_size == length(expected),
       "The stored Final family size does not match the declaration."},
      {result.study_revision_id == request.study_revision_id,
       "The stored Final study revision does not match the request."},
      {result.snapshot_id == request.snapshot_id,
       "The stored Final snapshot ID does not match the request."},
      {result.source_pilot_run_id == request.source_pilot_run_id,
       "The stored Final source Pilot ID does not match the request."},
      {result.plan_count == request.plan_count,
       "The stored Final plan count does not match the request."},
      {result.attacks_per_plan == request.attacks_per_plan,
       "The stored Final attack count does not match the request."},
      {Assertions.claim(result.assertions) == Assertions.claim(request.assertions),
       "The stored Final assertions do not match the request."}
    ]

    case Enum.find(checks, fn {holds, _message} -> not holds end) do
      nil -> :ok
      {_holds, message} -> invalid(message)
    end
  end

  defp check_counts(%__MODULE__{} = result, expected, members) do
    cond do
      length(result.comparisons) != length(expected) ->
        invalid("The stored Final family is incomplete.")

      length(members) != length(expected) ->
        invalid("The collected Final family does not match the declaration.")

      true ->
        :ok
    end
  end

  # Every comparison is checked in declared order and the first failure wins.
  # No check changes a comparison, so the validated result is returned as is.
  defp parse_comparisons(result, comparisons, members) do
    comparisons
    |> Enum.zip(members)
    |> Enum.reduce_while(:ok, fn {comparison, member}, :ok ->
      with :ok <- check_identity(comparison.identity, member.identity),
           :ok <- check_statistics(comparison.statistics, member) do
        {:cont, :ok}
      else
        {:error, %FinalError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      :ok -> {:ok, result}
      {:error, %FinalError{} = error} -> {:error, error}
    end
  end

  defp check_identity(%Identity{} = actual, %Identity{} = expected) do
    if Identity.matches?(actual, expected) do
      :ok
    else
      invalid("The stored Final comparison identities must follow the declared family order.")
    end
  end

  defp check_statistics(%ComparisonStatistics{} = statistics, member) do
    stored = ComparisonStatistics.to_params(statistics)
    collected = ComparisonStatistics.to_params(member.statistics)

    with true <- stored == collected,
         {:ok, _parsed} <- ComparisonStatistics.parse(stored, member.request) do
      :ok
    else
      _changed_or_invalid ->
        invalid("A stored Final comparison result does not match its collected member.")
    end
  end

  @doc false
  @spec validate_intrinsic(t()) :: :ok | {:error, FinalError.t()}
  def validate_intrinsic(%__MODULE__{} = result) do
    if result.family_size == length(result.comparisons) do
      validate_adjustments(result.comparisons, result.alpha)
    else
      invalid("The stored Final family is incomplete.")
    end
  end

  defp validate_adjustments(comparisons, alpha) do
    Enum.reduce_while(comparisons, :ok, fn comparison, :ok ->
      case check_adjustment(comparison.adjustment, comparison.statistics, alpha) do
        :ok -> {:cont, :ok}
        {:error, %FinalError{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  # A Holm correction cannot lower a p-value and cannot leave the unit
  # interval. These two relations are checked without repeating the correction
  # calculation.
  defp check_adjustment(%Adjustment{} = adjustment, statistics, alpha) do
    raw = statistics.test["raw_p_value"]
    adjusted = adjustment.adjusted_p_value

    cond do
      not is_number(adjusted) ->
        invalid("A stored Final adjustment has no adjusted p-value.")

      adjustment.reject_null != adjusted <= alpha ->
        invalid("A stored Final null-rejection decision does not follow the adjusted p-value.")

      adjusted < raw or adjusted > 1.0 ->
        invalid("A stored Final adjusted p-value is outside the Holm bounds.")

      true ->
        :ok
    end
  end

  defp invalid(message), do: {:error, FinalError.invalid_result(message)}
end
