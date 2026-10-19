defmodule NetworkDefense.Evaluation.Family.Contracts.FamilyResult do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics
  }

  alias NetworkDefense.Evaluation.Family.Contracts.{
    Adjustment,
    FamilyError,
    FamilyRequest,
    HolmResponse,
    Identity,
    ResultComparison
  }

  alias NetworkDefense.Evaluation.Family.SchemaValidator

  # Persisted family result. It keeps the per-comparison intervals unchanged
  # and adds one Holm adjustment row per declared identity.

  @type member :: %{
          identity: Identity.t(),
          request: ComparisonRequest.t(),
          statistics: ComparisonStatistics.t()
        }

  @type t :: %__MODULE__{
          schema_version: integer(),
          evidence_role: String.t(),
          family_id: String.t(),
          method: String.t(),
          alpha: float(),
          family_size: integer(),
          comparisons: [ResultComparison.t()]
        }

  embedded_schema do
    field(:schema_version, :integer)
    field(:evidence_role, :string)
    field(:family_id, :string)
    field(:method, :string)
    field(:alpha, :float)
    field(:family_size, :integer)
    embeds_many(:comparisons, ResultComparison, on_replace: :delete)
  end

  def changeset(result, attrs) do
    result
    |> change()
    |> SchemaValidator.matches_schema(attrs, :result)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(map(), FamilyRequest.t()) :: {:ok, t()} | {:error, FamilyError.t()}
  def parse(attrs, %FamilyRequest{} = request) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, result} ->
        validate_relations(result, request)

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           FamilyError.invalid_result("The stored family result could not be materialized.")
         )}
    end
  end

  @spec from_response(FamilyRequest.t(), [member()], HolmResponse.t()) ::
          {:ok, t()} | {:error, FamilyError.t()}
  def from_response(%FamilyRequest{} = request, members, %HolmResponse{} = response) do
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
      family_id: request.family_id,
      method: request.method,
      alpha: request.alpha,
      family_size: length(comparisons),
      comparisons: comparisons
    }

    parse(to_params(result), request)
  end

  defp cast_if_schema_valid(%Ecto.Changeset{valid?: false} = changeset, _attrs),
    do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:schema_version, :evidence_role, :family_id, :method, :alpha, :family_size])
    |> cast_embed(:comparisons, required: true)
  end

  defp validate_relations(%__MODULE__{} = result, %FamilyRequest{} = request) do
    expected = request.expected_comparisons
    expected_size = length(expected)
    requests = Map.new(request.comparisons, &{Identity.key(&1.identity), &1.request})

    cond do
      result.evidence_role != request.evidence_role ->
        invalid("The stored evidence role does not match the declaration.")

      result.family_id != request.family_id ->
        invalid("The stored family ID does not match the declaration.")

      result.method != request.method ->
        invalid("The stored correction method does not match the declaration.")

      result.alpha != request.alpha ->
        invalid("The stored alpha does not match the declaration.")

      result.family_size != expected_size ->
        invalid("The stored family size does not match the declaration.")

      length(result.comparisons) != expected_size ->
        invalid("The stored family is incomplete.")

      true ->
        with {:ok, comparisons} <-
               parse_members(result.comparisons, expected, requests, result.alpha) do
          {:ok, %{result | comparisons: comparisons}}
        end
    end
  end

  defp parse_members(comparisons, expected, requests, alpha) do
    comparisons
    |> Enum.zip(expected)
    |> Enum.reduce_while({:ok, []}, fn {comparison, identity}, {:ok, acc} ->
      with :ok <- check_identity(comparison.identity, identity),
           {:ok, request} <- fetch_request(requests, identity),
           {:ok, statistics} <- parse_statistics(comparison.statistics, request),
           :ok <- check_adjustment(comparison.adjustment, alpha) do
        {:cont, {:ok, [%{comparison | statistics: statistics} | acc]}}
      else
        {:error, %FamilyError{} = error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, comparisons} -> {:ok, Enum.reverse(comparisons)}
      {:error, %FamilyError{} = error} -> {:error, error}
    end
  end

  defp check_identity(%Identity{} = actual, %Identity{} = expected) do
    if Identity.matches?(actual, expected) do
      :ok
    else
      invalid("The stored comparison identities must follow the declared family order.")
    end
  end

  defp fetch_request(requests, %Identity{} = identity) do
    case Map.fetch(requests, Identity.key(identity)) do
      {:ok, %ComparisonRequest{} = request} -> {:ok, request}
      :error -> invalid("The stored identity has no supplied comparison request.")
    end
  end

  defp parse_statistics(%ComparisonStatistics{} = statistics, %ComparisonRequest{} = request) do
    case ComparisonStatistics.parse(ComparisonStatistics.to_params(statistics), request) do
      {:ok, %ComparisonStatistics{} = parsed} ->
        {:ok, parsed}

      {:error, %ComparisonError{}} ->
        invalid("A stored comparison result does not match its comparison request.")
    end
  end

  defp check_adjustment(%Adjustment{adjusted_p_value: adjusted, reject_null: reject_null}, alpha) do
    if reject_null != adjusted <= alpha do
      invalid("A stored null-rejection decision does not follow the adjusted p-value.")
    else
      :ok
    end
  end

  defp invalid(message), do: {:error, FamilyError.invalid_result(message)}
end
