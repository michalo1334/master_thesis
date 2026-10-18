defmodule NetworkDefense.Evaluation.ComparisonClientStub do
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

defmodule NetworkDefense.Evaluation.ComparisonClientTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Comparison.Client
  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonError, ComparisonRequest}

  @contracts_root Path.expand("../../../../contracts/evaluation/comparison/v1", __DIR__)

  setup do
    original = Application.fetch_env!(:network_defense, Client)
    on_exit(fn -> Application.put_env(:network_defense, Client, original) end)

    {:ok, request} =
      "valid/crossed-small.request.json" |> read_json() |> ComparisonRequest.parse()

    %{request: request}
  end

  test "CLIENT-01: 200 returns typed statistics and sends bounded canonical JSON", %{
    request: request
  } do
    statistics = read_json("valid/informative.statistics.json")
    agent = start_stub!(200, statistics)

    assert {:ok, result} = Client.compare(request)
    assert result.method == "corrected_crossed_bootstrap_v1"

    [body] = Agent.get(agent, & &1.requests)
    assert byte_size(body) <= 1_048_576
    assert %{"schema_version" => 1} = Jason.decode!(body)
  end

  test "CLIENT-02: documented client errors are permanent", %{request: request} do
    for {status, code} <- [
          {400, "invalid_json"},
          {413, "request_too_large"},
          {415, "unsupported_media_type"},
          {422, "validation_failed"}
        ] do
      start_stub!(status, error_envelope(code), unique: status)

      assert {:error, :permanent, %ComparisonError{code: ^code}} = Client.compare(request)
    end
  end

  test "CLIENT-03: 500 and 503 typed failures are temporary", %{request: request} do
    for {status, code} <- [{500, "compute_failed"}, {503, "compute_unavailable"}] do
      start_stub!(status, error_envelope(code), unique: status)

      assert {:error, :temporary, %ComparisonError{code: ^code}} = Client.compare(request)
    end
  end

  test "CLIENT-04: connection and response timeout failures are temporary", %{request: request} do
    Application.put_env(:network_defense, Client,
      base_url: "http://127.0.0.1:1",
      connect_timeout: 10,
      receive_timeout: 10
    )

    assert {:error, :temporary, %ComparisonError{code: "compute_unavailable"}} =
             Client.compare(request)

    start_stub!(200, read_json("valid/informative.statistics.json"), delay_ms: 100)
    config = Application.fetch_env!(:network_defense, Client)
    Application.put_env(:network_defense, Client, Keyword.put(config, :receive_timeout, 5))

    assert {:error, :temporary, %ComparisonError{code: "compute_unavailable"}} =
             Client.compare(request)
  end

  test "CLIENT-05: malformed and oversized success bodies are permanent", %{request: request} do
    for {body, unique} <- [{"{", 1}, {String.duplicate("x", 65_537), 2}, {%{}, 3}] do
      start_stub!(200, body, unique: unique)

      assert {:error, :permanent, %ComparisonError{code: "invalid_response_contract"}} =
               Client.compare(request)
    end
  end

  test "CLIENT-06: invalid error bodies and unknown statuses are permanent", %{request: request} do
    for {status, body, unique} <- [{503, %{}, 1}, {503, "{", 2}, {429, %{}, 3}] do
      start_stub!(status, body, unique: unique)

      assert {:error, :permanent, %ComparisonError{code: "invalid_response_contract"}} =
               Client.compare(request)
    end
  end

  test "CLIENT-07: invalid success relations are permanent", %{request: request} do
    invalid =
      "valid/informative.statistics.json"
      |> read_json()
      |> put_in(["interval", "lower"], 10.0)
      |> put_in(["interval", "upper"], -10.0)

    start_stub!(200, invalid)

    assert {:error, :permanent, %ComparisonError{code: "invalid_response_contract"}} =
             Client.compare(request)
  end

  test "HTTP-01: every non-object JSON response root is permanent", %{request: request} do
    roots = ["[]", "\"value\"", "1", "true", "null"]
    statuses = [200, 400, 413, 415, 422, 500, 503]

    for {status, status_index} <- Enum.with_index(statuses),
        {body, body_index} <- Enum.with_index(roots) do
      start_stub!(status, body, unique: {status_index, body_index})

      assert {:error, :permanent, %ComparisonError{code: "invalid_response_contract"}} =
               Client.compare(request)
    end
  end

  test "HTTP-03: schema-diagnostic 503 failures remain temporary", %{request: request} do
    envelope = %{
      "schema_version" => 1,
      "error" => %{
        "code" => "validation_failed",
        "schema_errors" => [
          %{"message" => "Invalid value.", "path" => ["value"], "causes" => []}
        ]
      }
    }

    start_stub!(503, envelope)

    assert {:error, :temporary, %ComparisonError{schema_errors: [_ | _]}} =
             Client.compare(request)
  end

  test "HTTP-05: programming errors are not relabeled as unavailability", %{request: request} do
    Application.put_env(:network_defense, Client, base_url: :invalid)
    assert_raise FunctionClauseError, fn -> Client.compare(request) end
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
         plug: {NetworkDefense.Evaluation.ComparisonClientStub, agent},
         ip: {127, 0, 0, 1},
         port: 0},
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
            "message" => "Safe error.",
            "details" => %{}
          }
        ]
      }
    }
  end

  defp read_json(relative_path) do
    @contracts_root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()
  end
end
