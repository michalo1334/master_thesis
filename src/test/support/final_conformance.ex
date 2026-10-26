defmodule NetworkDefense.Evaluation.FinalConformance do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonStatistics
  alias NetworkDefense.Evaluation.{EvidenceSnapshot, EvidenceSnapshots}
  alias NetworkDefense.Evaluation.Family.Contracts.{HolmRequest, HolmResponse, RawResult}

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    Result,
    SnapshotInput,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.{Member, Wire, Workflow}

  # Checked-in Final conformance examples.
  #
  # Python produced the member statistics and the Holm response. Elixir consumes
  # those files. Tests must not implement a second statistic.
  #
  # The Final evidence uses its own plan IDs, attack seeds, collection seeds,
  # and comparison seeds. It shares no observation with the Pilot fixture, so a
  # test cannot pass by leaking Pilot observations into Final inference.

  @root Path.expand("../../../contracts/evaluation/final/v1", __DIR__)
  @snapshot_path Path.join(@root, "valid/final-small.snapshot.json")
  @request_path Path.join(@root, "valid/final-small.request.json")
  @correction_request_path Path.join(@root, "valid/final-small.correction-request.json")
  @correction_response_path Path.join(@root, "valid/final-small.correction-response.json")
  @member_request_paths Path.wildcard(Path.join(@root, "valid/member-requests/*.json"))
  @member_response_paths Path.wildcard(Path.join(@root, "valid/member-responses/*.json"))

  for path <-
        [@snapshot_path, @request_path, @correction_request_path, @correction_response_path] ++
          @member_request_paths ++ @member_response_paths do
    @external_resource path
  end

  @snapshot @snapshot_path |> File.read!() |> Jason.decode!()
  @request @request_path |> File.read!() |> Jason.decode!()
  @correction_request @correction_request_path |> File.read!() |> Jason.decode!()
  @correction_response @correction_response_path |> File.read!() |> Jason.decode!()

  @member_requests @member_request_paths
                   |> Enum.sort_by(fn path ->
                     path |> Path.basename(".json") |> String.to_integer()
                   end)
                   |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))

  @member_responses @member_response_paths
                    |> Enum.sort_by(fn path ->
                      path |> Path.basename(".json") |> String.to_integer()
                    end)
                    |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))

  def root, do: @root
  def snapshot, do: @snapshot
  def request, do: @request
  def correction_request, do: @correction_request
  def correction_response, do: @correction_response
  def member_responses, do: @member_responses

  def fixture do
    %{
      snapshot: @snapshot,
      request: @request,
      correction_request: @correction_request,
      correction_response: @correction_response,
      member_requests: @member_requests,
      member_responses: @member_responses
    }
  end

  def read(relative_path),
    do: @root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()

  @spec snapshot_input!(map()) :: SnapshotInput.t()
  def snapshot_input!(fixture \\ fixture()),
    do: assert_ok(SnapshotInput.parse(fixture.snapshot))

  @spec parsed_payload!(map()) :: SnapshotPayload.t()
  def parsed_payload!(fixture \\ fixture()), do: snapshot_input!(fixture).payload

  @doc """
  Store one Final evidence snapshot through the snapshot boundary.

  The boundary validates the whole document and its encoded size before one
  insert, so a caller receives the same bounded errors a stored snapshot
  produces.
  """
  @spec store_snapshot(map()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, FinalError.t()}
  def store_snapshot(attrs) do
    with {:ok, input} <- SnapshotInput.parse(attrs),
         do: EvidenceSnapshots.create_final(input)
  end

  @doc """
  Submit one Final request through the Final workflow boundary.

  The workflow validates the request, its limits, its source binding, and its
  member work before a Gust run exists.
  """
  @spec submit(map()) :: {:ok, integer()} | {:error, FinalError.t()}
  def submit(attrs) do
    with {:ok, %Request{} = request} <- Request.parse(attrs) do
      request
      |> Wire.request()
      |> Workflow.submit()
    end
  end

  @spec request_params!(String.t(), integer()) :: map()
  def request_params!(snapshot_id, source_pilot_run_id) do
    request_params!(
      snapshot_id,
      source_pilot_run_id,
      @request["study_execution_id"],
      fixture()
    )
  end

  @spec request_params!(String.t(), integer(), String.t()) :: map()
  def request_params!(snapshot_id, source_pilot_run_id, study_execution_id) do
    request_params!(snapshot_id, source_pilot_run_id, study_execution_id, fixture())
  end

  @spec request_params!(String.t(), integer(), String.t(), map()) :: map()
  def request_params!(snapshot_id, source_pilot_run_id, study_execution_id, fixture) do
    fixture.request
    |> Map.put("snapshot_id", snapshot_id)
    |> Map.put("source_pilot_run_id", source_pilot_run_id)
    |> Map.put("study_execution_id", study_execution_id)
  end

  @spec parsed_request!(String.t(), integer()) :: Request.t()
  def parsed_request!(snapshot_id, source_pilot_run_id) do
    assert_ok(Request.parse(request_params!(snapshot_id, source_pilot_run_id)))
  end

  @spec parsed_request!(String.t(), integer(), String.t()) :: Request.t()
  def parsed_request!(snapshot_id, source_pilot_run_id, study_execution_id) do
    parsed_request!(snapshot_id, source_pilot_run_id, study_execution_id, fixture())
  end

  @spec parsed_request!(String.t(), integer(), String.t(), map()) :: Request.t()
  def parsed_request!(snapshot_id, source_pilot_run_id, study_execution_id, fixture) do
    assert_ok(
      Request.parse(
        request_params!(snapshot_id, source_pilot_run_id, study_execution_id, fixture)
      )
    )
  end

  @doc "One typed complete-family result for the supplied strict request."
  @spec result!(Request.t(), map()) :: Result.t()
  def result!(%Request{} = request, fixture \\ fixture()) do
    payload = parsed_payload!(fixture)

    members =
      payload.comparisons
      |> Enum.with_index()
      |> Enum.map(fn {comparison, position} ->
        comparison_request =
          request
          |> Member.comparison_request(payload, position)
          |> assert_ok()

        statistics =
          position
          |> response(fixture)
          |> ComparisonStatistics.parse(comparison_request)
          |> assert_ok()

        %{identity: comparison.identity, request: comparison_request, statistics: statistics}
      end)

    correction_request = %HolmRequest{
      schema_version: 1,
      family_id: request.family_id,
      method: request.method,
      alpha: request.analysis.alpha,
      expected_comparisons: request.expected_comparisons,
      raw_results:
        Enum.map(members, fn member ->
          %RawResult{
            identity: member.identity,
            raw_p_value: member.statistics.test["raw_p_value"] / 1
          }
        end)
    }

    correction =
      assert_ok(HolmResponse.parse(fixture.correction_response, correction_request))

    assert_ok(Result.from_response(request, members, correction))
  end

  defp response(position, fixture), do: Enum.at(fixture.member_responses, position)

  @doc """
  The exact comparison request maps the Final adapter must send, in declared order.

  Python wrote these files from the same evidence generation the snapshot uses.
  The stub matches received traffic against them, so a changed evidence value in
  the adapter cannot move the expectation with it.
  """
  @spec member_requests!(map()) :: [map()]
  def member_requests!(fixture \\ fixture()), do: fixture.member_requests

  @doc "Checked-in statistics for an exact Final member request."
  @spec response_for(map(), map()) :: map() | nil
  def response_for(generated_request, fixture \\ fixture()) do
    fixture.member_requests
    |> Enum.zip(fixture.member_responses)
    |> Enum.find_value(fn {request, response} ->
      if request == generated_request, do: response
    end)
  end

  @doc "Raw p-values in declared order, taken from the checked-in member responses."
  def raw_p_values(fixture \\ fixture()),
    do: Enum.map(fixture.member_responses, & &1["test"]["raw_p_value"])

  @doc """
  A bounded error envelope both evaluation endpoints accept.

  The envelope code and the issue code have separate vocabularies. Only the
  shared codes may repeat, so a `validation_failed` envelope carries the shared
  `invalid_type` issue code.
  """
  def error_envelope(code), do: error_envelope(code, shared_issue_code(code))

  def error_envelope(code, issue_code) do
    %{
      "schema_version" => 1,
      "error" => %{
        "code" => code,
        "issues" => [
          %{
            "code" => issue_code,
            "path" => [],
            "message" => "The request failed safely.",
            "details" => %{}
          }
        ]
      }
    }
  end

  # Envelope codes that are also issue codes may repeat. The rest need a
  # documented issue code, because an unknown issue code is a schema failure.
  defp shared_issue_code("validation_failed"), do: "invalid_type"
  defp shared_issue_code(code), do: code

  defp assert_ok({:ok, value}), do: value
  defp assert_ok({:error, error}), do: raise("expected ok, got: #{inspect(error)}")
end
