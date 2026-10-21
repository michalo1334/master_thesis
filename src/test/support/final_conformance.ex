defmodule NetworkDefense.Evaluation.FinalConformance do
  @moduledoc false

  alias NetworkDefense.Evaluation.Final.Contracts.{
    Request,
    SnapshotInput,
    SnapshotPayload
  }

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

  def read(relative_path),
    do: @root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()

  @spec snapshot_input!() :: SnapshotInput.t()
  def snapshot_input!, do: assert_ok(SnapshotInput.parse(@snapshot))

  @spec parsed_payload!() :: SnapshotPayload.t()
  def parsed_payload!, do: snapshot_input!().payload

  @spec request_params!(String.t(), integer()) :: map()
  def request_params!(snapshot_id, source_pilot_run_id) do
    @request
    |> Map.put("snapshot_id", snapshot_id)
    |> Map.put("source_pilot_run_id", source_pilot_run_id)
  end

  @spec parsed_request!(String.t(), integer()) :: Request.t()
  def parsed_request!(snapshot_id, source_pilot_run_id) do
    assert_ok(Request.parse(request_params!(snapshot_id, source_pilot_run_id)))
  end

  @doc """
  The exact comparison request maps the Final adapter must send, in declared order.

  Python wrote these files from the same evidence generation the snapshot uses.
  The stub matches received traffic against them, so a changed evidence value in
  the adapter cannot move the expectation with it.
  """
  @spec member_requests!() :: [map()]
  def member_requests!, do: @member_requests

  @doc "Checked-in statistics for an exact Final member request."
  @spec response_for(map()) :: map() | nil
  def response_for(generated_request) do
    @member_requests
    |> Enum.zip(@member_responses)
    |> Enum.find_value(fn {request, response} ->
      if request == generated_request, do: response
    end)
  end

  @doc "Raw p-values in declared order, taken from the checked-in member responses."
  def raw_p_values, do: Enum.map(@member_responses, & &1["test"]["raw_p_value"])

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
