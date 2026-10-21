defmodule NetworkDefense.Evaluation.Final.Member do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics,
    Evidence
  }

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    SnapshotPayload
  }

  # Mapping of one declared Final comparison.
  #
  # A declared item stays compact: one position and one identity. It never
  # carries an evidence matrix, because PostgreSQL owns Final evidence and Gust
  # stores run parameters and compact results only. The mapped comparison task
  # rebuilds the comparison request from the stored snapshot, so the matrix
  # travels from PostgreSQL to the compute service and is never persisted in
  # Gust.
  #
  # The submitted Final request supplies the analysis settings and the explicit
  # seed for the declared position.

  @type item :: %{position: non_neg_integer(), identity: Identity.t()}

  @type result :: %{identity: Identity.t(), statistics: ComparisonStatistics.t()}

  @type member :: %{
          identity: Identity.t(),
          request: ComparisonRequest.t(),
          statistics: ComparisonStatistics.t()
        }

  @spec declared_items(Request.t()) :: [map()]
  def declared_items(%Request{} = request) do
    request.expected_comparisons
    |> Enum.with_index()
    |> Enum.map(fn {identity, position} -> item_params(position, identity) end)
  end

  @spec item_params(non_neg_integer(), Identity.t()) :: map()
  def item_params(position, %Identity{} = identity) when is_integer(position) do
    %{"position" => position, "identity" => Identity.to_params(identity)}
  end

  @spec parse_item(term()) :: {:ok, item()} | {:error, FinalError.t()}
  def parse_item(%{"position" => position, "identity" => identity_attrs} = value)
      when map_size(value) == 2 and is_integer(position) and position >= 0 do
    with {:ok, identity} <- parse_identity(identity_attrs) do
      {:ok, %{position: position, identity: identity}}
    end
  end

  def parse_item(_value),
    do: {:error, FinalError.incomplete_family("A persisted Final member item is malformed.")}

  @doc """
  Build the accepted comparison request for one declared position.

  The evidence comes from the stored snapshot at that position, the seed and
  the analysis settings come from the submitted Final request. A position
  without a declared identity, a stored identity that differs from the declared
  identity, or a missing seed is a bounded error.

  The comparison parser owns the shared member byte cap. A generated request
  that exceeds that cap is a deterministic Final contract failure, so its
  bounded code is kept instead of escaping as a foreign comparison error.
  """
  @spec comparison_request(Request.t(), SnapshotPayload.t(), non_neg_integer()) ::
          {:ok, ComparisonRequest.t()} | {:error, FinalError.t()}
  def comparison_request(%Request{} = request, %SnapshotPayload{} = payload, position)
      when is_integer(position) and position >= 0 do
    with {:ok, identity} <- declared_identity(request, position),
         {:ok, comparison} <- stored_comparison(payload, position),
         :ok <- identity_agrees(comparison.identity, identity),
         {:ok, seed} <- declared_seed(request, position) do
      parse_comparison_request(comparison_request_attrs(comparison.evidence, seed, request))
    end
  end

  @doc """
  Build every declared comparison request before a run starts.

  The same builder serves this preflight, preparation, the mapped member, and
  the read-back. A request that would be rejected for its size therefore stops
  submission with no Gust run and no compute call, instead of failing inside a
  task.
  """
  @spec preflight(Request.t(), SnapshotPayload.t()) :: :ok | {:error, FinalError.t()}
  def preflight(%Request{} = request, %SnapshotPayload{} = payload) do
    request.expected_comparisons
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {_identity, position}, :ok ->
      case comparison_request(request, payload, position) do
        {:ok, _comparison_request} -> {:cont, :ok}
        {:error, %FinalError{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp parse_comparison_request(attrs) do
    case ComparisonRequest.parse(attrs) do
      {:ok, comparison_request} -> {:ok, comparison_request}
      {:error, %ComparisonError{} = error} -> {:error, FinalError.from_foreign(error)}
    end
  end

  defp comparison_request_attrs(evidence, seed, %Request{} = request) do
    %{
      "schema_version" => 1,
      "evidence" => Evidence.to_params(evidence),
      "resampling" => %{
        "seed" => seed,
        "replicates" => request.analysis.bootstrap_replicates
      },
      "interval" => %{"confidence_level" => request.analysis.confidence_level},
      "test" => %{"alternative" => request.analysis.test_alternative}
    }
  end

  defp declared_identity(%Request{} = request, position) do
    case Enum.at(request.expected_comparisons, position) do
      nil ->
        {:error,
         FinalError.incomplete_family("A Final member has no declared comparison position.")}

      identity ->
        {:ok, identity}
    end
  end

  defp declared_seed(%Request{} = request, position) do
    case Enum.at(request.comparison_seeds, position) do
      nil ->
        {:error,
         FinalError.incomplete_family("A declared Final comparison has no explicit seed.")}

      seed ->
        {:ok, seed}
    end
  end

  defp stored_comparison(%SnapshotPayload{} = payload, position) do
    case Enum.at(payload.comparisons, position) do
      nil ->
        {:error, FinalError.incomplete_family("A declared Final comparison has no snapshot row.")}

      comparison ->
        {:ok, comparison}
    end
  end

  defp identity_agrees(%Identity{} = stored, %Identity{} = declared) do
    if Identity.matches?(stored, declared) do
      :ok
    else
      {:error,
       FinalError.changed_snapshot(
         "The Final snapshot identity order differs from the declared order."
       )}
    end
  end

  @spec parse_identity(term()) :: {:ok, Identity.t()} | {:error, FinalError.t()}
  def parse_identity(attrs) do
    case Identity.new(attrs) do
      {:ok, identity} ->
        {:ok, identity}

      :error ->
        {:error, FinalError.incomplete_family("A persisted Final identity is malformed.")}
    end
  end

  @spec parse_result(term(), ComparisonRequest.t()) ::
          {:ok, result()} | {:error, FinalError.t()}
  def parse_result(
        %{"identity" => identity_attrs, "statistics" => statistics_attrs} = value,
        %ComparisonRequest{} = request
      )
      when map_size(value) == 2 do
    with {:ok, identity} <- parse_identity(identity_attrs),
         {:ok, statistics} <- parse_statistics(statistics_attrs, request) do
      {:ok, %{identity: identity, statistics: statistics}}
    end
  end

  def parse_result(_value, %ComparisonRequest{}),
    do: {:error, FinalError.incomplete_family("A persisted Final member result is malformed.")}

  defp parse_statistics(attrs, request) do
    case ComparisonStatistics.parse(attrs, request) do
      {:ok, statistics} ->
        {:ok, statistics}

      {:error, _error} ->
        {:error,
         FinalError.incomplete_family(
           "A persisted Final member does not contain valid comparison statistics."
         )}
    end
  end
end
