defmodule NetworkDefense.Evaluation.PilotConformance do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Pilot.{Wire, Work, Workflow}

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonRequest,
    EvidenceSnapshotInput,
    PilotError,
    PilotRequest,
    PilotResult,
    SnapshotPayload
  }

  # Checked-in Pilot conformance examples.
  #
  # Python computes the bootstrap intervals that appear in the candidate
  # responses and in the stored result. Elixir consumes those files. Tests must
  # not implement a second statistic.

  @root Path.expand("../../../contracts/evaluation/pilot/v1", __DIR__)
  @snapshot_path Path.join(@root, "valid/pilot-small.snapshot.json")
  @request_path Path.join(@root, "valid/pilot-small.request.json")
  @result_path Path.join(@root, "valid/pilot-small.result.json")

  @external_resource @snapshot_path
  @external_resource @request_path
  @external_resource @result_path

  @snapshot @snapshot_path |> File.read!() |> Jason.decode!()
  @request @request_path |> File.read!() |> Jason.decode!()
  @result @result_path |> File.read!() |> Jason.decode!()

  @candidate_response_paths Path.wildcard(Path.join(@root, "valid/candidate-responses/*.json"))
  for path <- @candidate_response_paths, do: @external_resource(path)

  @echoed_id_keys ["snapshot_id", "pilot_id", "study_revision_id", "family_id"]

  def root, do: @root
  def snapshot, do: @snapshot
  def request, do: @request
  def stored_result, do: @result

  def read(relative_path),
    do: @root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()

  def snapshot_input, do: EvidenceSnapshotInput.parse(@snapshot)

  @doc """
  Store one Pilot evidence snapshot through the snapshot boundary.

  The boundary validates the whole document before one insert, so a caller
  receives the same bounded errors a stored snapshot produces.
  """
  @spec store_snapshot(map()) ::
          {:ok, EvidenceSnapshot.t()} | {:error, PilotError.t()}
  def store_snapshot(attrs) do
    with {:ok, input} <- EvidenceSnapshotInput.parse(attrs),
         do: EvidenceSnapshots.create(input)
  end

  @doc """
  Submit one Pilot request through the Pilot workflow boundary.

  The request is admitted against its stored snapshot and its resource limits
  before a Gust run exists, which is the admission the study coordinator
  applies before it creates a Pilot run.
  """
  @spec submit(map()) :: {:ok, integer()} | {:error, PilotError.t()}
  def submit(attrs) do
    with {:ok, request} <- PilotRequest.parse(attrs),
         {:ok, snapshot, payload} <- EvidenceSnapshots.load(request.snapshot_id),
         :ok <- PilotRequest.matches_snapshot(request, snapshot, payload),
         :ok <- Work.preflight(request, payload) do
      request
      |> Wire.request()
      |> Workflow.submit()
    end
  end

  @spec snapshot_input!() :: EvidenceSnapshotInput.t()
  def snapshot_input! do
    assert_ok(EvidenceSnapshotInput.parse(@snapshot))
  end

  @spec parsed_request(map() | nil) :: PilotRequest.t()
  def parsed_request(overrides \\ nil) do
    attrs = if is_map(overrides), do: Map.merge(@request, overrides), else: @request
    assert_ok(PilotRequest.parse(attrs))
  end

  def request_params(snapshot_id), do: %{@request | "snapshot_id" => snapshot_id}

  @spec parsed_result!() :: PilotResult.t()
  def parsed_result! do
    request = parsed_request()
    payload = parsed_payload!()
    assert_ok(PilotResult.parse(@result, request, payload))
  end

  @spec parsed_payload!() :: SnapshotPayload.t()
  def parsed_payload!, do: snapshot_input!().payload

  @spec candidate_requests() :: [map()]
  def candidate_requests do
    payload = parsed_payload!()
    request = parsed_request()

    assert_ok(Work.canonical_items(request, payload))
    |> Enum.map(fn item ->
      {:ok, candidate_request} =
        Work.candidate_request(request, payload, item)

      CandidateComparisonRequest.to_params(candidate_request)
    end)
  end

  @spec candidate_responses() :: [map()]
  def candidate_responses do
    @candidate_response_paths
    |> Enum.sort_by(&Path.basename/1)
    |> Enum.map(&(&1 |> File.read!() |> Jason.decode!()))
  end

  # Match one generated request to its conformance response.
  #
  # The response echoes identity metadata. A database test stores the same
  # payload under a fresh snapshot ID, so the echoed identifiers are taken from
  # the generated request. Every other field must match exactly.
  @spec response_for(map()) :: map() | nil
  def response_for(generated_request) do
    candidate_requests()
    |> Enum.zip(candidate_responses())
    |> Enum.find_value(fn {request, response} ->
      if Map.drop(request, @echoed_id_keys) == Map.drop(generated_request, @echoed_id_keys),
        do: Map.merge(response, Map.take(generated_request, @echoed_id_keys))
    end)
  end

  def error_envelope(code) do
    %{
      "schema_version" => 1,
      "error" => %{
        "code" => code,
        "issues" => [
          %{
            "code" => code,
            "path" => [],
            "message" => "The request failed safely.",
            "details" => %{}
          }
        ]
      }
    }
  end

  defp assert_ok({:ok, value}), do: value
  defp assert_ok({:error, error}), do: raise("expected ok, got: #{inspect(error)}")
end
