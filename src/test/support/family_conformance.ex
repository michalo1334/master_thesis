defmodule NetworkDefense.Evaluation.FamilyConformance do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonRequest, ComparisonStatistics}
  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyRequest, Identity}

  # Shared family conformance examples.
  #
  # The correction request, the correction response, and the stored family
  # result are checked-in JSON files. Python produces them, Elixir consumes
  # them. Tests must not invent a second statistical implementation.

  @root Path.expand("../../../contracts/evaluation/family/v1", __DIR__)
  @request_path Path.join(@root, "valid/holm-small.request.json")
  @result_path Path.join(@root, "valid/holm-small.result.json")
  @correction_request_path Path.join(@root, "valid/holm-small.correction-request.json")
  @correction_response_path Path.join(@root, "valid/holm-small.correction-response.json")

  @external_resource @request_path
  @external_resource @result_path
  @external_resource @correction_request_path
  @external_resource @correction_response_path

  @request @request_path |> File.read!() |> Jason.decode!()
  @result @result_path |> File.read!() |> Jason.decode!()
  @correction_request @correction_request_path |> File.read!() |> Jason.decode!()
  @correction_response @correction_response_path |> File.read!() |> Jason.decode!()

  def root, do: @root
  def request, do: @request
  def stored_result, do: @result
  def correction_request, do: @correction_request
  def correction_response, do: @correction_response

  def read(relative_path),
    do: @root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()

  @spec parsed_request() :: FamilyRequest.t()
  def parsed_request do
    {:ok, %FamilyRequest{} = request} = FamilyRequest.parse(@request)
    request
  end

  @spec declared_keys() :: [Identity.key()]
  def declared_keys do
    @request["expected_comparisons"]
    |> Enum.map(fn identity ->
      {identity["tier"], identity["budget"], identity["alternative"], identity["reference"],
       identity["outcome"]}
    end)
  end

  @spec stored_comparisons() :: [map()]
  def stored_comparisons, do: @result["comparisons"]

  @spec raw_p_values() :: [number()]
  def raw_p_values do
    @result["comparisons"]
    |> Enum.map(& &1["statistics"]["test"]["raw_p_value"])
  end

  @spec adjusted_p_values() :: [number()]
  def adjusted_p_values do
    @result["comparisons"]
    |> Enum.map(& &1["adjustment"]["adjusted_p_value"])
  end

  @spec decisions() :: [boolean()]
  def decisions do
    @result["comparisons"]
    |> Enum.map(& &1["adjustment"]["reject_null"])
  end

  # Statistics by declared position, taken from the stored result.
  @spec statistics_by_index() :: [ComparisonStatistics.t()]
  def statistics_by_index do
    request = parsed_request()

    request.comparisons
    |> Enum.zip(@result["comparisons"])
    |> Enum.map(fn {input, stored} -> parse_statistics!(stored["statistics"], input.request) end)
  end

  # Statistics by seeded member request, so an HTTP stub can answer by request.
  @spec statistics_by_request() :: [{map(), map()}]
  def statistics_by_request do
    @request["comparisons"]
    |> Enum.zip(@result["comparisons"])
    |> Enum.map(fn {input, stored} -> {input["request"], stored["statistics"]} end)
  end

  @spec statistics_for_request(map()) :: map()
  def statistics_for_request(response_request) do
    statistics_by_request()
    |> Enum.find_value(fn {declared, statistics} ->
      if declared == response_request, do: statistics
    end)
    |> case do
      nil -> raise ArgumentError, "the request is not a declared conformance member"
      statistics -> statistics
    end
  end

  @spec members() :: [
          %{
            identity: Identity.t(),
            request: ComparisonRequest.t(),
            statistics: ComparisonStatistics.t()
          }
        ]
  def members do
    request = parsed_request()

    request.expected_comparisons
    |> Enum.zip(request.comparisons)
    |> Enum.zip(@result["comparisons"])
    |> Enum.map(fn {{identity, input}, stored} ->
      %{
        identity: identity,
        request: input.request,
        statistics: parse_statistics!(stored["statistics"], input.request)
      }
    end)
  end

  defp parse_statistics!(attrs, %ComparisonRequest{} = request) do
    {:ok, %ComparisonStatistics{} = statistics} = ComparisonStatistics.parse(attrs, request)
    statistics
  end
end
