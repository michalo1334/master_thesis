defmodule NetworkDefense.Evaluation.Pilot.PilotActionsTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.Flows

  alias NetworkDefense.Evaluation.Pilot.Actions.{EvaluateCandidateComparison, Prepare, Select}
  alias NetworkDefense.Evaluation.Pilot.Assembler
  alias NetworkDefense.Evaluation.Pilot.Client

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonRequest,
    CandidateComparisonResult,
    PilotError,
    PilotRequest,
    PilotResult
  }

  alias NetworkDefense.Evaluation.Pilot.{Limits, TaskFailure, TaskFailure.RetryableError, Work}
  alias NetworkDefense.Evaluation.PilotConformance
  alias NetworkDefense.Evaluations

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    owner = Sandbox.start_owner!(NetworkDefense.Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(owner)
      Sandbox.stop_owner(gust_owner)
    end)

    {:ok, dag} =
      Flows.create_dag(%{name: "evaluation_pilot_actions_#{System.unique_integer([:positive])}"})

    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())
    request = PilotConformance.parsed_request(%{"snapshot_id" => snapshot.id})

    %{dag: dag, snapshot: snapshot, request: request}
  end

  describe "ACTIONS-01: preparation" do
    test "expands one canonical item per candidate and comparison", %{
      dag: dag,
      request: request
    } do
      run_id = run!(dag, request)

      assert %{"gust_task_items" => items} = Prepare.execute([], %{run_id: run_id})
      assert Enum.count(items) == 8

      assert Enum.map(items, & &1["candidate_position"]) |> Enum.uniq() == [0, 1, 2, 3]

      assert Enum.map(items, &{&1["plan_count"], &1["attacks_per_plan"]}) |> Enum.uniq() ==
               [{5, 10}, {5, 12}, {6, 10}, {6, 12}]

      # Stream seeds depend on tier rank and within-tier occurrence only.
      assert Enum.map(items, & &1["stream_seed"]) ==
               [700_001, 1_700_001, 700_001, 1_700_001, 700_001, 1_700_001, 700_001, 1_700_001]

      assert {:ok, _items} =
               Work.canonical_items(request, PilotConformance.parsed_payload!())
    end

    test "rejects a persisted request that is invalid", %{dag: dag, request: request} do
      invalid =
        request
        |> PilotRequest.to_params()
        |> Map.put("candidate_grid", %{"plan_count_candidates" => [5, 5]})

      run_id = run!(dag, invalid)

      assert_raise NonRecError, fn -> Prepare.execute([], %{run_id: run_id}) end
    end

    test "rejects a candidate request that exceeds the byte limit", %{
      dag: dag,
      request: request
    } do
      run_id = run!(dag, request)
      original = Application.get_env(:network_defense, Limits)
      on_exit(fn -> Application.put_env(:network_defense, Limits, original) end)

      Application.put_env(
        :network_defense,
        Limits,
        Keyword.put(original, :candidate_request_bytes, 100)
      )

      exception = assert_raise(NonRecError, fn -> Prepare.execute([], %{run_id: run_id}) end)
      assert {:ok, %PilotError{code: "request_too_large"}} = decode(exception)
    end

    test "rejects a request whose snapshot is not stored", %{dag: dag, request: request} do
      params = PilotRequest.to_params(%{request | snapshot_id: Ecto.UUID.generate()})
      run_id = run!(dag, params)

      exception = assert_raise(NonRecError, fn -> Prepare.execute([], %{run_id: run_id}) end)
      assert {:ok, %PilotError{issues: [issue]}} = decode(exception)
      assert issue["code"] == "snapshot_not_found"
    end
  end

  describe "ACTIONS-02: one mapped candidate comparison" do
    test "returns compact row fields and echoes the declared identity", %{
      dag: dag,
      request: request
    } do
      run_id = run!(dag, request)
      configure_stub!()
      item = Enum.at(items!(request), 0)

      assert %{"candidate_position" => 0, "comparison_position" => 0} =
               row = EvaluateCandidateComparison.execute([item: item], %{run_id: run_id})

      assert row["plan_count"] == 5
      assert row["attacks_per_plan"] == 10
      assert is_float(row["guarded_half_width"])
      assert row["informative"] == true
      assert row["passes"] == false
    end

    test "a temporary compute failure is retryable and retries only that item", %{
      dag: dag,
      request: request
    } do
      run_id = run!(dag, request)
      agent = configure_stub!(fail_next: :temporary)
      [item | _rest] = items!(request)

      assert_raise RetryableError, fn ->
        EvaluateCandidateComparison.execute([item: item], %{run_id: run_id})
      end

      assert %{"candidate_position" => 0} =
               EvaluateCandidateComparison.execute([item: item], %{run_id: run_id})

      assert Agent.get(agent, &length(&1.requests)) == 2
      assert Enum.map(Agent.get(agent, & &1.requests), & &1["candidate_position"]) == [0, 0]
    end

    test "a permanent compute failure is not retryable", %{dag: dag, request: request} do
      run_id = run!(dag, request)
      configure_stub!(fail_next: :permanent)
      [item | _rest] = items!(request)

      exception =
        assert_raise(NonRecError, fn ->
          EvaluateCandidateComparison.execute([item: item], %{run_id: run_id})
        end)

      assert {:ok, %PilotError{code: "invalid_json"}} = decode(exception)
    end

    test "a changed work item is rejected before any compute call", %{
      dag: dag,
      request: request
    } do
      run_id = run!(dag, request)
      agent = configure_stub!()
      [item | _rest] = items!(request)
      changed = Map.put(item, "stream_seed", item["stream_seed"] + 1)

      exception =
        assert_raise(NonRecError, fn ->
          EvaluateCandidateComparison.execute([item: changed], %{run_id: run_id})
        end)

      assert {:ok, %PilotError{issues: [issue]}} = decode(exception)
      assert issue["code"] == "changed_candidate_result"
      assert Agent.get(agent, & &1.requests) == []
    end
  end

  describe "ACTIONS-03: selection fan-in" do
    test "assembles the stored rows and applies the declared selection rule", %{
      dag: dag,
      request: request
    } do
      run_id = prepared_run!(dag, request)

      stored = Select.execute([], %{run_id: run_id})
      assert is_map(stored)

      assert {:ok, %PilotResult{} = result} =
               PilotResult.parse(stored, request, PilotConformance.parsed_payload!())

      assert result.outcome == "recommended"
      assert result.recommendation.plan_count == 6
      assert result.recommendation.attacks_per_plan == 10
      assert Enum.count(result.candidate_results) == 8

      assert Enum.map(result.candidate_summaries, & &1.candidate_id) ==
               ["small", "small-wide", "large", "large-wide"]

      assert Enum.map(result.candidate_summaries, & &1.all_comparisons_passed) ==
               [false, false, true, true]
    end

    test "completion order does not change the result", %{dag: dag, request: request} do
      run_id = prepared_run!(dag, request, task_order: :reversed)
      stored = Select.execute([], %{run_id: run_id})

      assert {:ok, %PilotResult{} = result} =
               PilotResult.parse(stored, request, PilotConformance.parsed_payload!())

      assert result.recommendation.candidate_id == "large"
      assert Enum.map(result.candidate_results, & &1.comparison_position) |> Enum.uniq() == [0, 1]
    end

    test "a required non-informative comparison blocks a recommendation", %{
      request: request
    } do
      payload = PilotConformance.parsed_payload!()
      results = results_with_non_informative_comparison(request, payload)

      assert {:ok, %PilotResult{} = result} = Assembler.assemble(request, payload, results)

      assert result.outcome == "insufficient"
      assert result.recommendation == nil
      assert result.insufficient_reason == "no_passing_candidate"

      assert Enum.all?(result.candidate_summaries, fn summary ->
               summary.all_comparisons_informative == false and
                 summary.non_informative_comparison_positions == [1] and
                 summary.all_comparisons_passed == false
             end)
    end

    test "a missing mapped result is rejected", %{dag: dag, request: request} do
      run_id = prepared_run!(dag, request, task_count: 7)

      exception = assert_raise(NonRecError, fn -> Select.execute([], %{run_id: run_id}) end)
      assert {:ok, %PilotError{issues: [issue]}} = decode(exception)
      assert issue["code"] == "incomplete_pilot"
    end

    test "a changed mapped row is rejected", %{dag: dag, request: request} do
      run_id = prepared_run!(dag, request, mutate_row: fn row -> %{row | "passes" => true} end)

      exception = assert_raise(NonRecError, fn -> Select.execute([], %{run_id: run_id}) end)
      assert {:ok, %PilotError{}} = decode(exception)
    end

    test "a changed prepared item list is rejected", %{dag: dag, request: request} do
      run_id = prepared_run!(dag, request, mutate_prepare: fn items -> tl(items) end)

      exception = assert_raise(NonRecError, fn -> Select.execute([], %{run_id: run_id}) end)
      assert {:ok, %PilotError{issues: [issue]}} = decode(exception)
      assert issue["code"] == "incomplete_pilot"
    end
  end

  defp results_with_non_informative_comparison(%PilotRequest{} = request, payload) do
    {:ok, items} = Work.canonical_items(request, payload)

    Enum.map(items, fn item ->
      {:ok, candidate_request} = Work.candidate_request(request, payload, item)
      params = CandidateComparisonRequest.to_params(candidate_request)

      response =
        if item["comparison_position"] == 1 do
          params
          |> PilotConformance.response_for()
          |> Map.merge(%{"informative" => false, "passes" => false, "guarded_half_width" => 0.0})
        else
          PilotConformance.response_for(params)
        end

      {:ok, result} = CandidateComparisonResult.parse(response, candidate_request)
      result
    end)
  end

  defp run!(dag, %PilotRequest{} = request), do: run!(dag, PilotRequest.to_params(request))

  defp run!(dag, params) do
    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: params})
    run.id
  end

  defp items!(%PilotRequest{} = request) do
    {:ok, items} = Work.canonical_items(request, PilotConformance.parsed_payload!())
    items
  end

  defp rows!(request, items) do
    payload = PilotConformance.parsed_payload!()

    Enum.map(items, fn item ->
      {:ok, candidate_request} = Work.candidate_request(request, payload, item)
      params = CandidateComparisonRequest.to_params(candidate_request)
      response = PilotConformance.response_for(params)
      {:ok, result} = CandidateComparisonResult.parse(response, candidate_request)
      Work.result_params(result)
    end)
  end

  defp prepared_run!(dag, %PilotRequest{} = request, options \\ []) do
    run_id = run!(dag, request)
    items = items!(request)
    rows = rows!(request, items)

    prepared = Keyword.get(options, :mutate_prepare, & &1).(items)

    {:ok, _task} =
      Flows.create_task(%{
        name: "prepare_pilot",
        run_id: run_id,
        status: :succeeded,
        result: %{"gust_task_items" => prepared}
      })

    count = Keyword.get(options, :task_count, length(items))
    mutate_row = Keyword.get(options, :mutate_row, & &1)

    items
    |> Enum.zip(rows)
    |> Enum.take(count)
    |> Enum.with_index()
    |> then(fn pairs ->
      if Keyword.get(options, :task_order) == :reversed, do: Enum.reverse(pairs), else: pairs
    end)
    |> Enum.each(fn {{item, row}, index} ->
      {:ok, task} =
        Flows.create_task(%{
          name: "evaluate_candidate_comparison",
          run_id: run_id,
          map_index: index,
          status: :succeeded,
          result: mutate_row.(row)
        })

      {:ok, _task} = Flows.update_task_mapping(task, index, item)
    end)

    run_id
  end

  defp configure_stub!(options \\ []) do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{requests: [], fail_next: Keyword.get(options, :fail_next)}
         end}
      )

    server =
      start_supervised!(
        {Bandit,
         plug: {NetworkDefense.Evaluation.PilotActionsStub, agent}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    original = Application.fetch_env!(:network_defense, Client)
    Application.put_env(:network_defense, Client, base_url: "http://127.0.0.1:#{port}")
    on_exit(fn -> Application.put_env(:network_defense, Client, original) end)

    agent
  end

  defp decode(exception) do
    persisted = exception |> ErrorParser.parse() |> Jason.encode!() |> Jason.decode!()
    TaskFailure.decode(persisted)
  end
end

defmodule NetworkDefense.Evaluation.PilotActionsStub do
  @moduledoc false
  import Plug.Conn

  alias NetworkDefense.Evaluation.PilotConformance

  # Returns the checked-in conformance response for the exact request shape.
  # Failure injection proves retry and permanent paths without a second
  # statistical implementation.

  def init(agent), do: agent

  def call(conn, agent) do
    {:ok, body, conn} = read_body(conn)
    request = Jason.decode!(body)

    failure =
      Agent.get_and_update(agent, fn state ->
        {state.fail_next, %{state | requests: [request | state.requests], fail_next: nil}}
      end)

    {status, response} =
      case failure do
        :temporary ->
          {503, PilotConformance.error_envelope("compute_unavailable")}

        :permanent ->
          {400, PilotConformance.error_envelope("invalid_json")}

        nil ->
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
