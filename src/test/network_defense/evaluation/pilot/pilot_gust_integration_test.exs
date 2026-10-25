defmodule NetworkDefense.Evaluation.Pilot.GustIntegrationTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.Flows

  alias NetworkDefense.Evaluation.Pilot.Client
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotResult}
  alias NetworkDefense.Evaluation.Pilot.Work
  alias NetworkDefense.Evaluation.PilotConformance
  alias NetworkDefense.Evaluations

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    owner = Sandbox.start_owner!(NetworkDefense.Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(owner)
      Sandbox.stop_owner(gust_owner)
    end)

    start_supervised!(
      {Gust.DAG.Loader.Worker, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}}
    )

    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    wait_for_pilot_dag!()

    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())
    request_params = PilotConformance.request_params(snapshot.id)

    %{snapshot: snapshot, request_params: request_params}
  end

  test "E2E-01: the complete pilot stores one recommendation and runs every comparison", %{
    snapshot: snapshot,
    request_params: request_params
  } do
    agent = start_http_stub!()

    assert {:ok, run_id} = Evaluations.submit_pilot(request_params)
    assert {:ok, :succeeded} = Evaluations.await_pilot(run_id, 20_000)
    assert {:ok, %PilotResult{} = result} = Evaluations.get_pilot_result(run_id)

    assert result.outcome == "recommended"
    assert result.recommendation.candidate_id == "large"
    assert result.recommendation.plan_count == 6
    assert result.recommendation.attacks_per_plan == 10
    assert Enum.count(result.candidate_results) == 8

    expected = %{PilotConformance.stored_result() | "snapshot_id" => snapshot.id}
    assert PilotResult.to_params(result) == expected

    state = Agent.get(agent, & &1)
    assert Enum.count(state.requests) == 8

    assert Enum.map(state.requests, &{&1["candidate_position"], &1["comparison_position"]})
           |> Enum.sort() ==
             for(candidate <- 0..3, comparison <- 0..1, do: {candidate, comparison})

    assert Enum.all?(state.requests, &(&1["snapshot_id"] == snapshot.id))
  end

  test "E2E-02: the published result reads back through the public boundary", %{
    request_params: request_params
  } do
    start_http_stub!()

    assert {:ok, run_id} = Evaluations.submit_pilot(request_params)
    assert {:ok, :succeeded} = Evaluations.await_pilot(run_id, 20_000)

    assert {:ok, %PilotResult{} = first} = Evaluations.get_pilot_result(run_id)
    assert {:ok, %PilotResult{} = second} = Evaluations.get_pilot_result(run_id)
    assert first == second
  end

  test "E2E-03: persisted root, preparation, and mapped inputs match the declaration", %{
    request_params: request_params
  } do
    start_http_stub!()

    assert {:ok, run_id} = Evaluations.submit_pilot(request_params)
    assert {:ok, :succeeded} = Evaluations.await_pilot(run_id, 20_000)

    persisted = Flows.get_run_with_tasks!(run_id)
    assert persisted.params == request_params

    request = PilotConformance.parsed_request(%{"snapshot_id" => request_params["snapshot_id"]})
    prepare = Enum.find(persisted.tasks, &(&1.name == "prepare_pilot"))
    items = prepare.result["gust_task_items"]

    assert {:ok, expected_items} =
             Work.canonical_items(
               request,
               PilotConformance.parsed_payload!()
             )

    assert items == expected_items

    mapped =
      persisted.tasks
      |> Enum.filter(&(&1.name == "evaluate_candidate_comparison"))
      |> Enum.sort_by(& &1.map_index)

    assert Enum.map(mapped, & &1.map_index) == Enum.to_list(0..7)
    assert Enum.map(mapped, & &1.params) == expected_items
    assert Enum.all?(mapped, &(&1.attempt == 1))
  end

  test "E2E-04: a temporary failure retries only that candidate comparison", %{
    request_params: request_params
  } do
    use_immediate_retries!()
    agent = start_http_stub!(temporary_positions: [3])

    assert {:ok, run_id} = Evaluations.submit_pilot(request_params)
    assert {:ok, :succeeded} = Evaluations.await_pilot(run_id, 20_000)

    persisted = Flows.get_run_with_tasks!(run_id)

    attempts =
      persisted.tasks
      |> Enum.filter(&(&1.name == "evaluate_candidate_comparison"))
      |> Enum.sort_by(& &1.map_index)
      |> Enum.map(& &1.attempt)

    assert Enum.take(attempts, 6) == [1, 1, 1, 1, 1, 1]
    assert Enum.sort(Enum.drop(attempts, 6)) == [1, 2]
    assert {:ok, %PilotResult{}} = Evaluations.get_pilot_result(run_id)

    position_three =
      Enum.filter(Agent.get(agent, & &1.requests), &(&1["candidate_position"] == 3))

    assert Enum.count(position_three) == 3
  end

  test "E2E-05: a permanent failure fails the run with a typed pilot error", %{
    request_params: request_params
  } do
    start_http_stub!(permanent_positions: [1])

    assert {:ok, run_id} = Evaluations.submit_pilot(request_params)
    assert {:error, %PilotError{code: "invalid_json"}} = Evaluations.await_pilot(run_id, 20_000)
    assert {:error, %PilotError{}} = Evaluations.get_pilot_result(run_id)

    persisted = Flows.get_run_with_tasks!(run_id)
    assert persisted.status == :failed

    select = Enum.find(persisted.tasks, &(&1.name == "select_pilot"))
    assert select.status in [:upstream_failed, :pending]
    assert select.result in [nil, %{}]
  end

  defp start_http_stub!(options \\ []) do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             requests: [],
             temporary_positions: Keyword.get(options, :temporary_positions, []),
             permanent_positions: Keyword.get(options, :permanent_positions, []),
             delays: Keyword.get(options, :delays, %{})
           }
         end}
      )

    server =
      start_supervised!(
        {Bandit,
         plug: {NetworkDefense.Evaluation.PilotHTTPStub, agent}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    original = Application.fetch_env!(:network_defense, Client)
    Application.put_env(:network_defense, Client, base_url: "http://127.0.0.1:#{port}")
    on_exit(fn -> Application.put_env(:network_defense, Client, original) end)

    agent
  end

  defp use_immediate_retries! do
    original = Application.get_env(:gust, :dag_task_delayer)
    Application.put_env(:gust, :dag_task_delayer, NetworkDefense.Evaluation.PilotImmediateRetry)

    on_exit(fn ->
      if original do
        Application.put_env(:gust, :dag_task_delayer, original)
      else
        Application.delete_env(:gust, :dag_task_delayer)
      end
    end)
  end

  defp wait_for_pilot_dag! do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case Flows.get_dag_by_name("evaluation_pilot") do
        nil ->
          Process.sleep(10)
          {:cont, nil}

        dag ->
          {:halt, dag}
      end
    end) || flunk("Gust did not load evaluation_pilot")
  end
end

defmodule NetworkDefense.Evaluation.PilotImmediateRetry do
  @moduledoc false
  @behaviour Gust.DAG.TaskDelayer

  @impl true
  def calc_delay(_attempt), do: 0
end

defmodule NetworkDefense.Evaluation.PilotHTTPStub do
  @moduledoc false
  import Plug.Conn

  alias NetworkDefense.Evaluation.Pilot.Work
  alias NetworkDefense.Evaluation.PilotConformance

  # Answers each canonical candidate request with the checked-in conformance
  # response. Failure injection and delays stay deterministic.

  def init(agent), do: agent

  def call(conn, agent) do
    {:ok, body, conn} = read_body(conn)
    request = Jason.decode!(body)
    position = request["candidate_position"]

    {temporary?, permanent?, delay} =
      Agent.get_and_update(agent, fn state ->
        temporary? = position in state.temporary_positions
        permanent? = position in state.permanent_positions

        next = %{
          state
          | requests: [request | state.requests],
            temporary_positions: List.delete(state.temporary_positions, position)
        }

        {{temporary?, permanent?, Map.get(state.delays, position, 0)}, next}
      end)

    if delay > 0, do: Process.sleep(delay)

    {status, response} =
      cond do
        permanent? ->
          {400, PilotConformance.error_envelope("invalid_json")}

        temporary? ->
          {503, PilotConformance.error_envelope("compute_unavailable")}

        true ->
          case PilotConformance.response_for(request) do
            nil -> {422, PilotConformance.error_envelope("invalid_json")}
            response -> {200, response}
          end
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(response))
  end
end
