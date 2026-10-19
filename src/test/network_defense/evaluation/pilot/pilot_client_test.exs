defmodule NetworkDefense.Evaluation.PilotClientStub do
  @moduledoc false
  import Plug.Conn

  def init(agent), do: agent

  def call(conn, agent) do
    {:ok, request_body, conn} = read_body(conn)

    response =
      Agent.get_and_update(agent, fn state ->
        {state.response, %{state | requests: [request_body | state.requests]}}
      end)

    if response.delay_ms > 0, do: Process.sleep(response.delay_ms)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(response.status, encode(response.body))
  end

  defp encode(body) when is_binary(body), do: body
  defp encode(body), do: Jason.encode!(body)
end

defmodule NetworkDefense.Evaluation.Pilot.ClientTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Pilot.Client
  alias NetworkDefense.Evaluation.Pilot.Contracts.CandidateComparisonRequest
  alias NetworkDefense.Evaluation.Pilot.Contracts.CandidateComparisonResult
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError
  alias NetworkDefense.Evaluation.Pilot.Work
  alias NetworkDefense.Evaluation.PilotConformance

  # The request and response bodies are the checked-in conformance files, so the
  # transport test carries no second Pilot implementation.

  setup do
    original = Application.fetch_env!(:network_defense, Client)
    on_exit(fn -> Application.put_env(:network_defense, Client, original) end)
    :ok
  end

  test "CLIENT-01: a valid response returns the typed result" do
    agent = start_stub!(200, response_body())
    request = request!()

    assert {:ok, %CandidateComparisonResult{} = result} = Client.compare(request)
    assert result.candidate_position == request.candidate_position
    assert result.comparison_position == request.comparison_position
    assert result.passes == false

    [body] = Agent.get(agent, & &1.requests)
    decoded = Jason.decode!(body)
    assert decoded["candidate_position"] == request.candidate_position
    assert decoded["stream_seed"] == request.stream_seed
    refute Map.has_key?(decoded, "guarded_half_width")
  end

  test "CLIENT-02: documented client errors are permanent" do
    for {status, code} <- [
          {400, "invalid_json"},
          {413, "request_too_large"},
          {415, "unsupported_media_type"},
          {422, "validation_failed"}
        ] do
      start_stub!(status, error_envelope(code), unique: status)

      assert {:error, :permanent, %PilotError{code: ^code}} = Client.compare(request!())
    end
  end

  test "CLIENT-03: 500 and 503 typed failures are temporary" do
    for {status, code} <- [{500, "compute_failed"}, {503, "compute_unavailable"}] do
      start_stub!(status, error_envelope(code), unique: status)

      assert {:error, :temporary, %PilotError{code: ^code}} = Client.compare(request!())
    end
  end

  test "CLIENT-04: a connection failure is temporary" do
    put_client(base_url: "http://127.0.0.1:1", connect_timeout: 100, receive_timeout: 1_000)

    assert {:error, :temporary, %PilotError{code: code}} = Client.compare(request!())
    assert code == "compute_unavailable"
  end

  test "CLIENT-05: a receive timeout is temporary" do
    start_stub!(200, response_body(), delay_ms: 1_000, receive_timeout: 100)

    assert {:error, :temporary, %PilotError{code: code}} = Client.compare(request!())
    assert code == "compute_unavailable"
  end

  test "CLIENT-06: malformed and oversized success bodies are permanent" do
    for {body, name} <- [
          {"{\"not\": \"a result\"}", :malformed},
          {Map.put(response_body(), "padding", String.duplicate("x", 70_000)), :oversized}
        ] do
      start_stub!(200, body, unique: name)

      assert {:error, :permanent, %PilotError{code: code}} = Client.compare(request!())
      assert code == "invalid_response_contract"
    end
  end

  test "CLIENT-07: a changed response echo is rejected" do
    request = request!()
    body = Map.put(response_body(), "candidate_position", request.candidate_position + 1)
    start_stub!(200, body)

    assert {:error, :permanent, %PilotError{code: "validation_failed", issues: issues}} =
             Client.compare(request)

    assert Enum.any?(issues, &(&1["code"] == "changed_candidate_result"))
  end

  test "CLIENT-08: an invalid error body is a permanent invalid response" do
    start_stub!(422, %{"error" => "nope"})

    assert {:error, :permanent, %PilotError{code: "invalid_response_contract"}} =
             Client.compare(request!())
  end

  test "CLIENT-09: an unknown status is a permanent invalid response" do
    start_stub!(418, response_body())

    assert {:error, :permanent, %PilotError{code: "invalid_response_contract"}} =
             Client.compare(request!())
  end

  test "CLIENT-10: a missing base URL is not relabeled as a transport failure" do
    put_client([])

    assert_raise FunctionClauseError, fn -> Client.compare(request!()) end
  end

  defp request! do
    payload = PilotConformance.parsed_payload!()
    request = PilotConformance.parsed_request()
    {:ok, items} = Work.canonical_items(request, payload)
    {:ok, candidate_request} = Work.candidate_request(request, payload, hd(items))

    assert {:ok, %CandidateComparisonRequest{} = parsed} =
             CandidateComparisonRequest.parse(
               CandidateComparisonRequest.to_params(candidate_request)
             )

    parsed
  end

  defp response_body, do: PilotConformance.response_for(hd(PilotConformance.candidate_requests()))

  defp start_stub!(status, body, options \\ []) do
    response = %{status: status, body: body, delay_ms: Keyword.get(options, :delay_ms, 0)}
    unique = Keyword.get_lazy(options, :unique, &System.unique_integer/0)

    agent_spec =
      Supervisor.child_spec(
        {Agent, fn -> %{response: response, requests: []} end},
        id: {__MODULE__, :agent, unique}
      )

    agent = start_supervised!(agent_spec)

    server_spec =
      Supervisor.child_spec(
        {Bandit,
         plug: {NetworkDefense.Evaluation.PilotClientStub, agent}, ip: {127, 0, 0, 1}, port: 0},
        id: {__MODULE__, :server, unique}
      )

    server = start_supervised!(server_spec)

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    put_client(
      base_url: "http://127.0.0.1:#{port}",
      connect_timeout: Keyword.get(options, :connect_timeout, 100),
      receive_timeout: Keyword.get(options, :receive_timeout, 1_000)
    )

    agent
  end

  defp put_client(options) do
    Application.put_env(:network_defense, Client, Keyword.merge([base_url: nil], options))
  end

  defp error_envelope(code) do
    issue_code = if code == "validation_failed", do: "invalid_candidate_result", else: code

    %{
      "schema_version" => 1,
      "error" => %{
        "code" => code,
        "issues" => [
          %{
            "code" => issue_code,
            "path" => [],
            "message" => "The compute service rejected the request.",
            "details" => %{}
          }
        ]
      }
    }
  end
end
