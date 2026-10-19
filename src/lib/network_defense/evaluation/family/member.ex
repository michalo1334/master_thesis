defmodule NetworkDefense.Evaluation.Family.Member do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonRequest,
    ComparisonStatistics
  }

  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyRequest, Identity}

  # Structural parsing for persisted family members.
  #
  # These shapes are Gust storage records, not wire contracts. The nested
  # comparison contracts still own their own strict validation.

  @type input :: %{identity: Identity.t(), request: ComparisonRequest.t()}
  @type result :: %{identity: Identity.t(), statistics: ComparisonStatistics.t()}

  @input_keys ["identity", "request"]
  @result_keys ["identity", "statistics"]
  @input_arity length(@input_keys)
  @result_arity length(@result_keys)

  # Canonical mapped-item parameters for one validated family request.
  #
  # Items follow the declared order. Preparation stores them, and collection
  # compares the persisted copies with them. One builder keeps both sides
  # equal by construction.
  @spec canonical_items(FamilyRequest.t()) :: {:ok, [map()]} | {:error, FamilyError.t()}
  def canonical_items(%FamilyRequest{} = request) do
    supplied =
      Map.new(request.comparisons, fn input -> {Identity.key(input.identity), input.request} end)

    request.expected_comparisons
    |> Enum.reduce_while({:ok, []}, fn identity, {:ok, acc} ->
      case Map.fetch(supplied, Identity.key(identity)) do
        {:ok, %ComparisonRequest{} = comparison_request} ->
          {:cont, {:ok, [item_params(identity, comparison_request) | acc]}}

        :error ->
          {:halt, {:error, missing_declaration()}}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      {:error, error} -> {:error, error}
    end
  end

  @spec item_params(Identity.t(), ComparisonRequest.t()) :: map()
  def item_params(%Identity{} = identity, %ComparisonRequest{} = request) do
    %{
      "identity" => Identity.to_params(identity),
      "request" => ComparisonRequest.to_params(request)
    }
  end

  defp missing_declaration do
    FamilyError.incomplete_family(
      "The validated family request is missing a declared comparison."
    )
  end

  @spec parse_input(term()) :: {:ok, input()} | {:error, FamilyError.t()}
  def parse_input(%{"identity" => identity_attrs, "request" => request_attrs} = value)
      when map_size(value) == @input_arity do
    with {:ok, identity} <- parse_identity(identity_attrs),
         {:ok, request} <- parse_request(request_attrs),
         :ok <- check_agreement(identity, request) do
      {:ok, %{identity: identity, request: request}}
    end
  end

  def parse_input(_value),
    do: {:error, FamilyError.incomplete_family("A persisted family member input is malformed.")}

  @spec parse_result(term(), ComparisonRequest.t()) ::
          {:ok, result()} | {:error, FamilyError.t()}
  def parse_result(
        %{"identity" => identity_attrs, "statistics" => statistics_attrs} = value,
        %ComparisonRequest{} = request
      )
      when map_size(value) == @result_arity do
    with {:ok, identity} <- parse_identity(identity_attrs),
         {:ok, statistics} <- parse_statistics(statistics_attrs, request) do
      {:ok, %{identity: identity, statistics: statistics}}
    end
  end

  def parse_result(_value, %ComparisonRequest{}),
    do: {:error, FamilyError.incomplete_family("A persisted family member result is malformed.")}

  @spec parse_identity(term()) :: {:ok, Identity.t()} | {:error, FamilyError.t()}
  def parse_identity(attrs) do
    case Identity.new(attrs) do
      {:ok, identity} ->
        {:ok, identity}

      :error ->
        {:error, FamilyError.incomplete_family("A persisted family identity is malformed.")}
    end
  end

  defp parse_request(attrs) do
    case ComparisonRequest.parse(attrs) do
      {:ok, request} ->
        {:ok, request}

      {:error, _error} ->
        {:error,
         FamilyError.incomplete_family(
           "A persisted family member does not contain a valid comparison request."
         )}
    end
  end

  defp parse_statistics(attrs, request) do
    case ComparisonStatistics.parse(attrs, request) do
      {:ok, statistics} ->
        {:ok, statistics}

      {:error, _error} ->
        {:error,
         FamilyError.incomplete_family(
           "A persisted family member does not contain valid comparison statistics."
         )}
    end
  end

  defp check_agreement(%Identity{} = identity, %ComparisonRequest{} = request) do
    if identity.alternative == request.evidence.alternative.strategy and
         identity.reference == request.evidence.reference.strategy and
         identity.outcome == request.evidence.outcome do
      :ok
    else
      {:error,
       FamilyError.incomplete_family(
         "A persisted family identity does not agree with its comparison request."
       )}
    end
  end
end
