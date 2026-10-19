defmodule NetworkDefense.Evaluation.FamilyActionsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.Flows

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonRequest, ComparisonStatistics}
  alias NetworkDefense.Evaluation.Family.Actions.{CompareMember, CorrectFamily, Prepare}
  alias NetworkDefense.Evaluation.Family.Client
  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyRequest, Identity}
  alias NetworkDefense.Evaluation.Family.{TaskFailure, TaskFailure.RetryableError}
  alias NetworkDefense.Evaluation.FamilyConformance

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    {:ok, dag} =
      Gust.Flows.create_dag(%{
        name: "evaluation_family_actions_#{System.unique_integer([:positive])}"
      })

    %{dag: dag}
  end

  test "ACTIONS-01: prepare expands the declared order one member per identity", %{dag: dag} do
    request = family_request!()

    {:ok, run} =
      Flows.create_run(%{dag_id: dag.id, params: FamilyRequest.to_params(request)})

    assert %{"gust_task_items" => [_first, _second, _third, _fourth] = items} =
             Prepare.execute([], %{run_id: run.id})

    assert Enum.map(items, & &1["identity"]["budget"]) == [4, 6, 4, 6]
    assert Enum.map(items, & &1["identity"]["tier"]) == ["core", "core", "edge", "edge"]
    assert Enum.all?(items, &match?(%{"identity" => _, "request" => _}, &1))
  end

  test "ACTIONS-02: prepare rejects invalid persisted parameters permanently", %{dag: dag} do
    invalid = FamilyConformance.read("invalid/missing-comparison.request.json")
    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: invalid})

    assert_raise NonRecError, fn -> Prepare.execute([], %{run_id: run.id}) end
  end

  test "ACTIONS-03: prepare rejects a persisted request with an invalid nested comparison", %{
    dag: dag
  } do
    invalid = FamilyConformance.read("invalid/nested-attack-column-mismatch.request.json")
    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: invalid})

    exception = assert_raise(NonRecError, fn -> Prepare.execute([], %{run_id: run.id}) end)

    persisted = exception |> ErrorParser.parse() |> Jason.encode!() |> Jason.decode!()

    assert {:ok, %{issues: issues}} = TaskFailure.decode(persisted)

    assert Enum.any?(issues, &(&1["code"] == "attack_column_count_mismatch"))
  end

  test "ACTIONS-04: the member adapter returns the identity with the comparison result", %{
    dag: dag
  } do
    request = family_request!()

    {:ok, run} =
      Flows.create_run(%{dag_id: dag.id, params: FamilyRequest.to_params(request)})

    %{"gust_task_items" => [item | _rest]} = Prepare.execute([], %{run_id: run.id})
    configure_stub!(statistics: FamilyConformance.statistics_for_request(item["request"]))

    assert %{"identity" => identity, "statistics" => statistics} =
             CompareMember.execute([item: item], %{run_id: run.id})

    assert identity == item["identity"]
    assert statistics["test"]["raw_p_value"] == Enum.at(FamilyConformance.raw_p_values(), 0)
  end

  test "ACTIONS-05: the member adapter rejects a malformed item permanently" do
    assert_raise NonRecError, fn ->
      CompareMember.execute([item: %{"identity" => %{}, "request" => %{}}], %{run_id: -1})
    end
  end

  test "ACTIONS-06: the fan-in task corrects and stores the complete family", %{dag: dag} do
    request = family_request!()
    run_id = prepared_run!(dag, request)
    configure_stub!()

    stored = CorrectFamily.execute([], %{run_id: run_id})

    assert stored["family_id"] == "primary-comparisons-small"
    assert stored["evidence_role"] == "synthetic_prototype"
    assert stored["family_size"] == 4

    assert Enum.map(stored["comparisons"], & &1["adjustment"]["adjusted_p_value"]) ==
             FamilyConformance.adjusted_p_values()

    assert Enum.map(stored["comparisons"], & &1["adjustment"]["reject_null"]) ==
             FamilyConformance.decisions()

    assert Enum.map(stored["comparisons"], & &1["identity"]["budget"]) == [4, 6, 4, 6]

    # The stored result is the checked-in conformance example.
    assert stored == FamilyConformance.stored_result()
  end

  test "ACTIONS-07: the fan-in task rejects an incomplete persisted family", %{dag: dag} do
    request = family_request!()
    run_id = prepared_run!(dag, request, member_count: 2)
    configure_stub!()

    assert_raise NonRecError, fn -> CorrectFamily.execute([], %{run_id: run_id}) end
  end

  test "ACTIONS-08: the fan-in task retries when the correction service is unavailable", %{
    dag: dag
  } do
    request = family_request!()
    run_id = prepared_run!(dag, request)
    configure_stub!(fail_first_correction: true)

    assert_raise RetryableError, fn -> CorrectFamily.execute([], %{run_id: run_id}) end
  end

  test "ACTIONS-09: a non-informative member stays in the corrected family", %{dag: dag} do
    request = family_request!()
    run_id = prepared_run!(dag, request)
    configure_stub!()

    stored = CorrectFamily.execute([], %{run_id: run_id})

    assert stored["family_size"] == 4

    third = Enum.at(stored["comparisons"], 2)
    assert third["statistics"]["assessment"]["status"] == "non_informative"
    assert third["statistics"]["test"]["raw_p_value"] == 1.0
    assert third["adjustment"]["adjusted_p_value"] == 1.0
    assert third["adjustment"]["reject_null"] == false
  end

  test "ACTIONS-10: mapped completion order does not change the stored family", %{dag: dag} do
    request = family_request!()
    declared_run = prepared_run!(dag, request)
    configure_stub!()
    declared = CorrectFamily.execute([], %{run_id: declared_run})
    reversed_run = prepared_run!(dag, request, task_order: :reversed)
    reversed = CorrectFamily.execute([], %{run_id: reversed_run})

    assert reversed == declared

    assert Enum.map(reversed["comparisons"], & &1["identity"]["budget"]) == [4, 6, 4, 6]
  end

  test "ACTIONS-11: a changed persisted seed stops the family before the correction call", %{
    dag: dag
  } do
    request = family_request!()

    run_id =
      prepared_run!(dag, request,
        mutate_mapped: fn index, item ->
          if index == 1,
            do: put_in(item, ["request", "resampling", "seed"], 900_002),
            else: item
        end
      )

    agent = configure_stub!()

    assert_raise NonRecError, fn -> CorrectFamily.execute([], %{run_id: run_id}) end

    state = Agent.get(agent, & &1)
    assert state.correction_requests == []
    assert Flows.get_tasks_by_name("correct_family", run_id) == []
  end

  test "ACTIONS-12: a changed persisted analysis setting stops the family before the correction call",
       %{dag: dag} do
    request = family_request!()

    run_id =
      prepared_run!(dag, request,
        mutate_mapped: fn index, item ->
          if index == 2,
            do: put_in(item, ["request", "interval", "confidence_level"], 0.9),
            else: item
        end
      )

    agent = configure_stub!()

    assert_raise NonRecError, fn -> CorrectFamily.execute([], %{run_id: run_id}) end

    assert Agent.get(agent, & &1).correction_requests == []
  end

  test "ACTIONS-13: a changed persisted preparation stops the family before the correction call",
       %{
         dag: dag
       } do
    request = family_request!()

    run_id =
      prepared_run!(dag, request,
        mutate_prepare: fn [first | rest] ->
          [put_in(first, ["request", "resampling", "seed"], 900_001) | rest]
        end
      )

    agent = configure_stub!()

    assert_raise NonRecError, fn -> CorrectFamily.execute([], %{run_id: run_id}) end

    assert Agent.get(agent, & &1).correction_requests == []
  end

  test "ACTIONS-14: stored statistics must match the submitted request", %{dag: dag} do
    request = family_request!()

    run_id =
      prepared_run!(dag, request,
        statistics: fn index, statistics ->
          if index == 0,
            do: put_in(statistics, ["interval", "confidence_level"], 0.9),
            else: statistics
        end
      )

    configure_stub!()

    assert_raise NonRecError, fn -> CorrectFamily.execute([], %{run_id: run_id}) end
  end

  test "ACTIONS-15: prepare rejects a malformed persisted identity without raising an exception",
       %{dag: dag} do
    marker = "leaked-identity-token"
    base = FamilyConformance.read("valid/holm-small.request.json")

    cases = [
      {"object identity", %{"mark" => marker}},
      {"oversized identity", String.duplicate(marker, 10_000)},
      {"list identity", [marker]}
    ]

    for {name, identity} <- cases do
      params =
        base
        |> put_in(["comparisons", Access.at(0), "identity", "tier"], identity)
        |> put_in(["comparisons", Access.at(0), "request"], %{})

      {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: params})

      exception = assert_raise(NonRecError, fn -> Prepare.execute([], %{run_id: run.id}) end)

      assert byte_size(exception.message) < 4096, name
      refute exception.message =~ marker, name

      assert {:ok, %FamilyError{code: "validation_failed", issues: []}} =
               TaskFailure.decode(%{
                 "type" => "Gust.DAG.NonRecError",
                 "message" => exception.message
               })
    end
  end

  defp prepared_run!(dag, request, options \\ []) do
    {:ok, run} =
      Flows.create_run(%{dag_id: dag.id, params: FamilyRequest.to_params(request)})

    declared = declared_items(request)
    items = Enum.take(declared, Keyword.get(options, :member_count, length(declared)))
    prepare_items = Keyword.get(options, :mutate_prepare, & &1).(items)
    statistics = FamilyConformance.statistics_by_index()
    mutate_mapped = Keyword.get(options, :mutate_mapped, fn _index, item -> item end)
    mutate_statistics = Keyword.get(options, :statistics, fn _index, stats -> stats end)

    {:ok, _prepare} =
      Flows.create_task(%{
        name: "prepare_family",
        run_id: run.id,
        status: :succeeded,
        result: %{"gust_task_items" => prepare_items}
      })

    items
    |> Enum.with_index()
    |> then(fn pairs ->
      if Keyword.get(options, :task_order) == :reversed, do: Enum.reverse(pairs), else: pairs
    end)
    |> Enum.each(fn {item, index} ->
      item = mutate_mapped.(index, item)

      {:ok, task} =
        Flows.create_task(%{
          name: "compare_member",
          run_id: run.id,
          map_index: index,
          status: :succeeded,
          result: %{
            "identity" => item["identity"],
            "statistics" =>
              statistics
              |> Enum.at(index)
              |> ComparisonStatistics.to_params()
              |> then(&mutate_statistics.(index, &1))
          }
        })

      {:ok, _task} = Flows.update_task_mapping(task, index, item)
    end)

    run.id
  end

  defp declared_items(%FamilyRequest{} = request) do
    request
    |> request_comparison_inputs()
    |> Enum.map(fn input ->
      %{
        "identity" => Identity.to_params(input.identity),
        "request" => ComparisonRequest.to_params(input.request)
      }
    end)
  end

  defp request_comparison_inputs(%FamilyRequest{} = request) do
    rank = fn input ->
      Enum.find_index(request.expected_comparisons, &Identity.matches?(&1, input.identity))
    end

    Enum.sort_by(request.comparisons, rank)
  end

  defp configure_stub!(options \\ []) do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             statistics: Keyword.get(options, :statistics),
             correction_requests: [],
             fail_first_correction: Keyword.get(options, :fail_first_correction, false)
           }
         end}
      )

    server =
      start_supervised!(
        {Bandit,
         plug: {NetworkDefense.Evaluation.FamilyActionsStub, agent}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    for client <- [Client, NetworkDefense.Evaluation.Comparison.Client] do
      original = Application.fetch_env!(:network_defense, client)
      Application.put_env(:network_defense, client, base_url: "http://127.0.0.1:#{port}")
      on_exit(fn -> Application.put_env(:network_defense, client, original) end)
    end

    agent
  end

  defp family_request!, do: FamilyConformance.parsed_request()
end

defmodule NetworkDefense.Evaluation.FamilyActionsStub do
  @moduledoc false
  import Plug.Conn

  alias NetworkDefense.Evaluation.FamilyConformance

  # The correction endpoint answers the checked-in correction request with the
  # checked-in correction response. Tests do not implement Holm again.

  def init(agent), do: agent

  def call(conn, agent) do
    {:ok, body, conn} = read_body(conn)
    request = Jason.decode!(body)

    {status, response} =
      case conn.request_path do
        "/v1/comparisons/corrected-crossed-bootstrap" ->
          {200, Agent.get(agent, & &1.statistics)}

        "/v1/families/holm" ->
          correction(request, agent)
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(response))
  end

  defp correction(request, agent) do
    fail? =
      Agent.get_and_update(agent, fn state ->
        remaining = if state.fail_first_correction, do: 1, else: 0

        {remaining > 0,
         %{
           state
           | correction_requests: [request | state.correction_requests],
             fail_first_correction: false
         }}
      end)

    cond do
      request != FamilyConformance.correction_request() ->
        {422,
         %{
           "schema_version" => 1,
           "error" => %{
             "code" => "validation_failed",
             "issues" => [
               %{
                 "code" => "invalid_correction",
                 "path" => [],
                 "message" => "The correction request does not match the conformance example.",
                 "details" => %{}
               }
             ]
           }
         }}

      fail? ->
        {503,
         %{
           "schema_version" => 1,
           "error" => %{
             "code" => "compute_unavailable",
             "issues" => [
               %{
                 "code" => "compute_unavailable",
                 "path" => [],
                 "message" => "The compute service is unavailable.",
                 "details" => %{}
               }
             ]
           }
         }}

      true ->
        {200, FamilyConformance.correction_response()}
    end
  end
end
