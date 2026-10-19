defmodule NetworkDefense.Evaluation.FamilyClientStub do
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

defmodule NetworkDefense.Evaluation.Family.FamilyClientTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Family.Client
  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, HolmRequest}
  alias NetworkDefense.Evaluation.FamilyConformance

  # The correction request and response are the checked-in conformance files,
  # so the transport test carries no second Holm implementation.

  defp request! do
    {:ok, %HolmRequest{} = request} = HolmRequest.parse(FamilyConformance.correction_request())
    request
  end

  defp response_body, do: FamilyConformance.correction_response()

  setup do
    original = Application.fetch_env!(:network_defense, Client)
    on_exit(fn -> Application.put_env(:network_defense, Client, original) end)
    :ok
  end

  test "CLIENT-01: 200 returns the typed correction and sends a small bounded body" do
    agent = start_stub!(200, response_body())

    assert {:ok, response} = Client.holm(request!())
    assert response.family_size == 4

    assert Enum.map(response.results, & &1.adjusted_p_value) ==
             FamilyConformance.adjusted_p_values()

    [body] = Agent.get(agent, & &1.requests)
    decoded = Jason.decode!(body)
    assert byte_size(body) <= 65_536
    assert Map.has_key?(decoded, "raw_results")
    refute Map.has_key?(decoded, "evidence")
  end

  test "CLIENT-02: documented client errors are permanent" do
    for {status, code} <- [
          {400, "invalid_json"},
          {413, "request_too_large"},
          {415, "unsupported_media_type"},
          {422, "validation_failed"}
        ] do
      start_stub!(status, error_envelope(code), unique: status)

      assert {:error, :permanent, %FamilyError{code: ^code}} = Client.holm(request!())
    end
  end

  test "CLIENT-03: 500 and 503 typed failures are temporary" do
    for {status, code} <- [{500, "compute_failed"}, {503, "compute_unavailable"}] do
      start_stub!(status, error_envelope(code), unique: status)

      assert {:error, :temporary, %FamilyError{code: ^code}} = Client.holm(request!())
    end
  end

  test "CLIENT-04: connection and response timeout failures are temporary" do
    Application.put_env(:network_defense, Client,
      base_url: "http://127.0.0.1:1",
      connect_timeout: 10,
      receive_timeout: 10
    )

    assert {:error, :temporary, %FamilyError{code: "compute_unavailable"}} =
             Client.holm(request!())

    start_stub!(200, response_body(), delay_ms: 100)
    config = Application.fetch_env!(:network_defense, Client)
    Application.put_env(:network_defense, Client, Keyword.put(config, :receive_timeout, 5))

    assert {:error, :temporary, %FamilyError{code: "compute_unavailable"}} =
             Client.holm(request!())
  end

  test "CLIENT-05: malformed and oversized success bodies are permanent" do
    for {body, unique} <- [{"{", 1}, {String.duplicate("x", 65_537), 2}, {%{}, 3}] do
      start_stub!(200, body, unique: unique)

      assert {:error, :permanent, %FamilyError{code: "invalid_response_contract"}} =
               Client.holm(request!())
    end
  end

  test "CLIENT-06: invalid error bodies and unknown statuses are permanent" do
    for {status, body, unique} <- [{503, %{}, 1}, {503, "{", 2}, {429, %{}, 3}] do
      start_stub!(status, body, unique: unique)

      assert {:error, :permanent, %FamilyError{code: "invalid_response_contract"}} =
               Client.holm(request!())
    end
  end

  test "CLIENT-07: an uncorrelated response is permanent" do
    body = put_in(response_body(), ["results", Access.at(0), "raw_p_value"], 0.5)

    start_stub!(200, body)

    assert {:error, :permanent, %FamilyError{code: "invalid_response_contract", issues: [issue]}} =
             Client.holm(request!())

    assert issue["path"] == ["results", 0, "raw_p_value"]
  end

  test "CLIENT-08: programming errors are not relabeled as unavailability" do
    Application.put_env(:network_defense, Client, base_url: :invalid)

    assert_raise FunctionClauseError, fn -> Client.holm(request!()) end
  end

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
         plug: {NetworkDefense.Evaluation.FamilyClientStub, agent}, ip: {127, 0, 0, 1}, port: 0},
        id: {__MODULE__, :server, unique}
      )

    server = start_supervised!(server_spec)

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    Application.put_env(:network_defense, Client,
      base_url: "http://127.0.0.1:#{port}",
      connect_timeout: 100,
      receive_timeout: 1_000
    )

    agent
  end

  defp error_envelope(code) do
    issue_code = if code == "validation_failed", do: "invalid_type", else: code

    %{
      "schema_version" => 1,
      "error" => %{
        "code" => code,
        "issues" => [
          %{
            "code" => issue_code,
            "path" => [],
            "message" => "The correction request failed safely.",
            "details" => %{}
          }
        ]
      }
    }
  end
end
