defmodule NetworkDefense.Evaluation.FamilyHTTPStub do
  @moduledoc false

  import Plug.Conn

  alias NetworkDefense.Evaluation.FamilyConformance

  # One stub for both compute endpoints.
  #
  # The comparison endpoint answers a request only when that exact request is a
  # declared member, and it answers with the checked-in conformance statistics.
  # The correction endpoint answers the checked-in correction request with the
  # checked-in correction response. Tests do not implement statistics or Holm
  # again. Failure injection stays available for retry and failure tests.

  def init(agent), do: agent

  def call(conn, agent) do
    {:ok, body, conn} = read_body(conn)
    request = if body == "", do: %{}, else: Jason.decode!(body)

    {status, response} =
      case conn.request_path do
        "/v1/comparisons/corrected-crossed-bootstrap" ->
          comparison(request, agent)

        "/v1/families/holm" ->
          correction(request, agent)

        _other ->
          {404, %{"error" => "unknown"}}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(response))
  end

  # One declared seed can fail permanently or once. A one-shot failure proves
  # that a temporary member error retries only that member.
  defp comparison(request, agent) do
    seed = get_in(request, ["resampling", "seed"])

    failure =
      Agent.get_and_update(agent, fn state ->
        temporary = Map.get(state, :temporary_seeds, [])
        always = Map.get(state, :always_temporary_seeds, [])

        failure =
          cond do
            seed in Map.get(state, :fail_seeds, []) -> :permanent
            seed in always -> :temporary
            seed in temporary -> :temporary
            true -> nil
          end

        state =
          state
          |> Map.put(:comparison_seeds, [seed | state.comparison_seeds])
          |> Map.put(:temporary_seeds, temporary -- [seed])

        {failure, state}
      end)

    Process.sleep(Map.get(Agent.get(agent, & &1), :slow_seeds, %{}) |> Map.get(seed, 0))

    Agent.update(agent, fn state ->
      Map.update(state, :completion_order, [seed], &[seed | &1])
    end)

    case failure do
      :permanent -> {400, error_envelope("invalid_json")}
      :temporary -> {503, error_envelope("compute_unavailable")}
      nil -> declared_statistics(request)
    end
  end

  defp declared_statistics(request) do
    Enum.find_value(FamilyConformance.statistics_by_request(), fn {declared, statistics} ->
      if declared == request, do: {200, statistics}
    end) || {422, error_envelope("validation_failed")}
  end

  defp correction(request, agent) do
    fail? =
      Agent.get_and_update(agent, fn state ->
        remaining = Map.get(state, :fail_corrections, 0)

        next =
          state
          |> Map.put(:correction_requests, [request | state.correction_requests])
          |> Map.put(:fail_corrections, max(remaining - 1, 0))

        {remaining > 0, next}
      end)

    cond do
      request != FamilyConformance.correction_request() ->
        {422, error_envelope("validation_failed")}

      fail? ->
        {503, error_envelope("compute_unavailable")}

      true ->
        {200, FamilyConformance.correction_response()}
    end
  end

  defp error_envelope(code) do
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
end

defmodule NetworkDefense.Evaluation.FamilyImmediateRetry do
  @moduledoc false
  @behaviour Gust.DAG.TaskDelayer

  @impl true
  def calc_delay(_attempt), do: 0
end

defmodule NetworkDefense.Evaluation.FamilySlowRetry do
  @moduledoc """
  Holds a failed task in the retry window so a test can observe it.

  The default Gust delayer uses a backoff that is too short for a stable
  observation point. A fixed delay keeps the test deterministic.
  """

  @behaviour Gust.DAG.TaskDelayer
  @delay 2_000

  @impl true
  def calc_delay(_attempt), do: @delay
end

defmodule NetworkDefense.Evaluation.Family.GustIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Evaluation.Comparison.Actions.Compare
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonRequest
  alias NetworkDefense.Evaluation.Family.Client

  alias NetworkDefense.Evaluation.Family.Contracts.{
    FamilyError,
    FamilyRequest,
    FamilyResult,
    Identity
  }

  alias NetworkDefense.Evaluation.Family.Wire
  alias NetworkDefense.Evaluation.FamilyConformance
  alias NetworkDefense.Evaluations

  @declared_seeds [700_001, 700_002, 700_003, 700_010]

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    start_supervised!(
      {Gust.DAG.Loader.Worker, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}}
    )

    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    wait_for_family_dag!()
    :ok
  end

  test "E2E-01: the complete declared family is corrected once and stored in order" do
    agent = start_http_stub!()
    request = FamilyConformance.request()

    assert {:ok, run_id} = Evaluations.submit_family(request)
    assert {:ok, :succeeded} = Evaluations.await_family(run_id, 10_000)
    assert {:ok, %FamilyResult{} = result} = Evaluations.get_family_result(run_id)

    assert result.family_size == 4
    assert result.evidence_role == "synthetic_prototype"
    assert result.method == "holm"

    assert Enum.map(result.comparisons, &Identity.key(&1.identity)) ==
             FamilyConformance.declared_keys()

    assert Enum.map(result.comparisons, & &1.statistics.test["raw_p_value"]) ==
             FamilyConformance.raw_p_values()

    assert Enum.map(result.comparisons, & &1.statistics.estimate["value"]) == [
             -1.4440000000000008,
             -1.4440000000000008,
             0.0,
             -0.5
           ]

    assert Enum.map(result.comparisons, & &1.adjustment.adjusted_p_value) ==
             FamilyConformance.adjusted_p_values()

    assert Enum.map(result.comparisons, & &1.adjustment.reject_null) == [true, true, false, false]

    # Intervals stay per-comparison values from the comparison step.
    assert Enum.map(result.comparisons, & &1.statistics.interval["lower"]) == [
             -1.5312098363463427,
             -1.5289117393074858,
             0.0,
             -0.9266210913158839
           ]

    state = Agent.get(agent, & &1)
    assert Enum.sort(state.comparison_seeds) == @declared_seeds
    assert [correction] = state.correction_requests

    assert correction == FamilyConformance.correction_request()
    assert Enum.map(correction["expected_comparisons"], & &1["budget"]) == [4, 6, 4, 6]

    assert Enum.map(correction["raw_results"], & &1["raw_p_value"]) ==
             FamilyConformance.raw_p_values()

    # The published result equals the checked-in conformance example.
    assert FamilyResult.to_params(result) == FamilyConformance.stored_result()
  end

  test "E2E-02: the published result reads back through the public boundary" do
    start_http_stub!()
    request = FamilyConformance.request()

    assert {:ok, run_id} = Evaluations.submit_family(request)
    assert {:ok, :succeeded} = Evaluations.await_family(run_id, 10_000)

    assert {:ok, %FamilyResult{} = first} = Evaluations.get_family_result(run_id)
    assert {:ok, %FamilyResult{} = second} = Evaluations.get_family_result(run_id)
    assert first == second
    assert FamilyResult.to_params(first) == FamilyConformance.stored_result()
  end

  test "E2E-03: an invalid public request creates no family run" do
    before_count = Gust.Repo.aggregate(Gust.Flows.Run, :count)
    invalid = FamilyConformance.read("invalid/identity-mismatch.request.json")

    assert {:error, %FamilyError{code: "validation_failed", issues: [issue]}} =
             Evaluations.submit_family(invalid)

    assert issue["code"] == "identity_mismatch"
    assert Gust.Repo.aggregate(Gust.Flows.Run, :count) == before_count
  end

  test "E2E-04: a retry after a temporary correction failure reuses comparison results" do
    use_immediate_retries!()
    request = FamilyConformance.request()

    agent =
      start_supervised!(
        {Agent, fn -> %{comparison_seeds: [], correction_requests: [], fail_corrections: 1} end}
      )

    start_stub_server!(agent)

    assert {:ok, run_id} = Evaluations.submit_family(request)
    assert {:ok, :succeeded} = Evaluations.await_family(run_id, 10_000)

    state = Agent.get(agent, & &1)
    assert [_, _] = state.correction_requests
    assert Enum.sort(state.comparison_seeds) == @declared_seeds

    persisted = Gust.Flows.get_run_with_tasks!(run_id)
    correction = Enum.find(persisted.tasks, &(&1.name == "correct_family"))
    assert correction.attempt == 2

    members = Enum.filter(persisted.tasks, &(&1.name == "compare_member"))
    assert Enum.all?(members, &(&1.attempt == 1))
    assert Enum.all?(members, &(&1.status == :succeeded))
  end

  test "E2E-05: a permanent member failure keeps its comparison error code" do
    agent =
      start_supervised!(
        {Agent, fn -> %{comparison_seeds: [], correction_requests: [], fail_seeds: [700_003]} end}
      )

    start_stub_server!(agent)
    request = FamilyConformance.request()

    assert {:ok, run_id} = Evaluations.submit_family(request)
    assert {:error, %FamilyError{code: "invalid_json"}} = Evaluations.await_family(run_id, 10_000)

    state = Agent.get(agent, & &1)
    assert state.correction_requests == []

    persisted = Gust.Flows.get_run_with_tasks!(run_id)
    correction = Enum.find(persisted.tasks, &(&1.name == "correct_family"))
    assert correction.status == :upstream_failed

    # One coordinator lifetime allows one initial execution and three retries.
    assert Application.get_env(:gust, :dag_stage_coordinator) == nil
    assert Enum.all?(persisted.tasks, &(&1.attempt <= 4))
  end

  test "E2E-06: the family member adapter keeps the accepted comparison behavior" do
    start_http_stub!()
    request = FamilyConformance.request()
    {:ok, %FamilyRequest{} = parsed} = FamilyRequest.parse(request)
    [first | _rest] = parsed.comparisons

    run = create_run!(parsed)

    statistics =
      Compare.execute(
        [
          request: ComparisonRequest.to_params(first.request)
        ],
        %{run_id: run.id}
      )

    assert statistics["test"]["raw_p_value"] == Enum.at(FamilyConformance.raw_p_values(), 0)
    assert statistics["assessment"]["status"] == "informative"
  end

  test "E2E-07: a temporary mapped failure retries only that member" do
    use_immediate_retries!()
    request = FamilyConformance.request()

    agent =
      start_supervised!(
        {Agent,
         fn -> %{comparison_seeds: [], correction_requests: [], temporary_seeds: [700_003]} end}
      )

    start_stub_server!(agent)

    assert {:ok, run_id} = Evaluations.submit_family(request)
    assert {:ok, :succeeded} = Evaluations.await_family(run_id, 10_000)

    persisted = Gust.Flows.get_run_with_tasks!(run_id)

    members =
      persisted.tasks
      |> Enum.filter(&(&1.name == "compare_member"))
      |> Enum.sort_by(& &1.map_index)

    assert Enum.map(members, & &1.attempt) == [1, 1, 2, 1]
    assert Enum.all?(members, &(&1.status == :succeeded))

    state = Agent.get(agent, & &1)
    assert [correction] = state.correction_requests

    assert Enum.map(correction["raw_results"], & &1["raw_p_value"]) ==
             FamilyConformance.raw_p_values()
  end

  test "E2E-08: persisted root, preparation, and mapped inputs match the declaration" do
    start_http_stub!()
    request = FamilyConformance.request()

    assert {:ok, run_id} = Evaluations.submit_family(request)
    assert {:ok, :succeeded} = Evaluations.await_family(run_id, 10_000)

    persisted = Gust.Flows.get_run_with_tasks!(run_id)
    assert persisted.params == request

    prepare = Enum.find(persisted.tasks, &(&1.name == "prepare_family"))
    items = prepare.result["gust_task_items"]

    assert Enum.map(items, & &1["identity"]["budget"]) == [4, 6, 4, 6]

    members =
      persisted.tasks
      |> Enum.filter(&(&1.name == "compare_member"))
      |> Enum.sort_by(& &1.map_index)

    assert Enum.map(members, & &1.map_index) == [0, 1, 2, 3]

    Enum.zip(members, items)
    |> Enum.each(fn {member, item} ->
      assert member.params == item
      assert member.result["identity"] == item["identity"]
    end)
  end

  test "E2E-09: a different mapped completion order gives an identical result" do
    request = FamilyConformance.request()
    agent = start_http_stub!()

    assert {:ok, fast_run} = Evaluations.submit_family(request)
    assert {:ok, :succeeded} = Evaluations.await_family(fast_run, 10_000)
    assert {:ok, %FamilyResult{} = fast} = Evaluations.get_family_result(fast_run)

    # A later declaration finishes first. Distinct delays fix the order, and
    # the declared order must not move.
    Agent.update(
      agent,
      &Map.put(&1, :slow_seeds, %{700_001 => 400, 700_002 => 300, 700_003 => 200, 700_010 => 100})
    )

    assert {:ok, slow_run} = Evaluations.submit_family(request)
    assert {:ok, :succeeded} = Evaluations.await_family(slow_run, 10_000)
    assert {:ok, %FamilyResult{} = slow} = Evaluations.get_family_result(slow_run)

    # The stub finishes the declared members in reverse order for the second
    # run. The persisted result must not move.
    {first_order, second_order} = agent |> completion_order() |> Enum.split(4)
    assert Enum.sort(first_order) == [0, 1, 2, 3]
    assert second_order == [3, 2, 1, 0]

    assert Enum.map(slow.comparisons, &Identity.key(&1.identity)) ==
             declared_keys(request)

    assert slow == fast
  end

  test "E2E-10: two runs of the same family share no state and give equal results" do
    request = FamilyConformance.request()

    agent =
      start_supervised!({Agent, fn -> %{comparison_seeds: [], correction_requests: []} end})

    start_stub_server!(agent)

    assert {:ok, first_run} = Evaluations.submit_family(request)
    assert {:ok, second_run} = Evaluations.submit_family(request)

    assert {:ok, :succeeded} = Evaluations.await_family(first_run, 10_000)
    assert {:ok, :succeeded} = Evaluations.await_family(second_run, 10_000)

    assert {:ok, first} = Evaluations.get_family_result(first_run)
    assert {:ok, second} = Evaluations.get_family_result(second_run)
    assert first == second

    state = Agent.get(agent, & &1)

    assert Enum.frequencies(state.comparison_seeds) == %{
             700_001 => 2,
             700_002 => 2,
             700_003 => 2,
             700_010 => 2
           }

    assert Enum.count(state.correction_requests) == 2
  end

  @tag :gust_restart_gap
  test "E2E-11: a coordinator restart starts a new in-memory retry budget" do
    # Characterization of the pinned Gust 0.1.40 contract. The limit of four
    # executions (one initial and three retries) lives in the coordinator
    # process. A reclaimed run builds a fresh coordinator, so the durable
    # attempt count passes four. The run must still stop safely, store no
    # result, and make no correction call.
    use_slow_retries!()
    use_fast_reclaim!()
    request = FamilyConformance.request()

    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             comparison_seeds: [],
             correction_requests: [],
             always_temporary_seeds: [700_003]
           }
         end}
      )

    start_stub_server!(agent)
    assert {:ok, run_id} = Evaluations.submit_family(request)

    wait_until(fn ->
      Gust.Flows.get_tasks_by_name("compare_member", run_id)
      |> Enum.any?(&(&1.map_index == 2 and &1.status == :retrying))
    end)

    [{first_pid, _value}] = Registry.lookup(Gust.Registry, "dag_run_#{run_id}")
    Process.exit(first_pid, :kill)

    Process.sleep(1_500)
    send(Gust.Run.Claimer, :claim_runs)

    # A different coordinator process claims the abandoned run.
    wait_until(fn ->
      case Registry.lookup(Gust.Registry, "dag_run_#{run_id}") do
        [{pid, _value}] -> pid != first_pid
        _other -> false
      end
    end)

    wait_until(
      fn ->
        Gust.Flows.get_tasks_by_name("compare_member", run_id)
        |> Enum.any?(&(&1.map_index == 2 and &1.status in [:failed, :succeeded]))
      end,
      1_200
    )

    member =
      Gust.Flows.get_tasks_by_name("compare_member", run_id)
      |> Enum.find(&(&1.map_index == 2))

    assert member.status == :failed

    # The durable count passes the four executions of one coordinator lifetime.
    assert member.attempt > 4

    wait_until(fn -> Gust.Flows.get_run!(run_id).status in [:failed, :succeeded] end)
    assert Gust.Flows.get_run!(run_id).status == :failed

    state = Agent.get(agent, & &1)
    assert state.correction_requests == []
    assert Map.fetch!(Enum.frequencies(state.comparison_seeds), 700_003) > 4

    # No family result exists, so the restart created no scientific outcome.
    assert {:error, %FamilyError{}} = Evaluations.get_family_result(run_id)
  end

  test "E2E-12: one coordinator lifetime allows four executions before it fails" do
    # Deterministic characterization without a restart: the failed member runs
    # once and retries three times, then the run fails safely.
    use_immediate_retries!()
    request = FamilyConformance.request()

    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             comparison_seeds: [],
             correction_requests: [],
             always_temporary_seeds: [700_003]
           }
         end}
      )

    start_stub_server!(agent)
    assert {:ok, run_id} = Evaluations.submit_family(request)
    assert {:error, %FamilyError{}} = Evaluations.await_family(run_id, 10_000)

    persisted = Gust.Flows.get_run_with_tasks!(run_id)

    member =
      persisted.tasks
      |> Enum.filter(&(&1.name == "compare_member"))
      |> Enum.find(&(&1.map_index == 2))

    assert member.status == :failed
    assert member.attempt == 4
    assert persisted.status == :failed

    state = Agent.get(agent, & &1)
    assert Enum.count(state.comparison_seeds, &(&1 == 700_003)) == 4

    assert Enum.sort(Enum.reject(state.comparison_seeds, &(&1 == 700_003))) ==
             [700_001, 700_002, 700_010]

    assert state.correction_requests == []

    assert {:error, %FamilyError{}} = Evaluations.get_family_result(run_id)
  end

  test "E2E-13: every invalid root request creates no family run" do
    invalid_paths =
      FamilyConformance.root()
      |> Path.join("invalid/*.request.json")
      |> Path.wildcard()
      |> Enum.sort()

    assert Enum.count(invalid_paths) == 8
    start_http_stub!()

    Enum.each(invalid_paths, fn path ->
      name = Path.basename(path)
      before_count = Gust.Repo.aggregate(Gust.Flows.Run, :count)

      assert {:error, %FamilyError{code: code}} =
               path |> File.read!() |> Jason.decode!() |> Evaluations.submit_family()

      assert code == "validation_failed", name
      assert Gust.Repo.aggregate(Gust.Flows.Run, :count) == before_count, name
    end)
  end

  test "E2E-14: a malformed identity raises nothing and creates no family run" do
    # Every case pairs a malformed identity with a malformed member. The schema
    # must reject the identity before any nested diagnostic reads it, so no
    # submitted value reaches an exception message or the error envelope.
    marker = "leaked-identity-token"

    malformed_identity =
      put_in(
        FamilyConformance.read("valid/holm-small.request.json"),
        ["comparisons", Access.at(0), "identity", "tier"],
        %{"mark" => marker}
      )

    oversized_identity =
      put_in(
        FamilyConformance.read("valid/holm-small.request.json"),
        ["comparisons", Access.at(0), "identity", "tier"],
        String.duplicate(marker, 10_000)
      )

    list_identity =
      put_in(
        FamilyConformance.read("valid/holm-small.request.json"),
        ["comparisons", Access.at(0), "identity"],
        [marker]
      )

    cases = [
      {"object identity", malformed_identity},
      {"oversized identity", oversized_identity},
      {"list identity", list_identity}
    ]

    start_http_stub!()

    for {name, request} <- cases do
      request = put_in(request, ["comparisons", Access.at(0), "request"], %{})
      before_count = Gust.Repo.aggregate(Gust.Flows.Run, :count)

      assert {:error, %FamilyError{code: "validation_failed"} = error} =
               Evaluations.submit_family(request)

      assert Gust.Repo.aggregate(Gust.Flows.Run, :count) == before_count, name

      assert error.issues == []
      assert error.schema_errors != []

      envelope = Jason.encode!(%{"schema_version" => 1, "error" => Wire.error(error)})
      assert byte_size(envelope) < 4096, name
      refute envelope =~ marker, name
    end
  end

  defp completion_order(agent) do
    seeds =
      agent
      |> Agent.get(&Map.get(&1, :completion_order, []))
      |> Enum.reverse()

    Enum.map(seeds, fn seed -> Enum.find_index(@declared_seeds, &(&1 == seed)) end)
  end

  defp declared_keys(request) do
    request
    |> Map.fetch!("expected_comparisons")
    |> Enum.map(fn identity ->
      {identity["tier"], identity["budget"], identity["alternative"], identity["reference"],
       identity["outcome"]}
    end)
  end

  defp wait_until(fun, tries \\ 400)

  defp wait_until(fun, tries) do
    cond do
      fun.() -> :ok
      tries <= 0 -> flunk("condition not met")
      true -> Process.sleep(25) && wait_until(fun, tries - 1)
    end
  end

  defp use_fast_reclaim! do
    original =
      Enum.map([:reclaim_run_delay, :claim_lease_seconds], &{&1, Application.get_env(:gust, &1)})

    Application.put_env(:gust, :reclaim_run_delay, 300)
    Application.put_env(:gust, :claim_lease_seconds, 1)

    on_exit(fn ->
      Enum.each(original, fn
        {key, nil} -> Application.delete_env(:gust, key)
        {key, value} -> Application.put_env(:gust, key, value)
      end)
    end)
  end

  defp create_run!(%FamilyRequest{} = request) do
    dag = Gust.Flows.get_dag_by_name("evaluation_family")

    {:ok, run} =
      Gust.Flows.create_run(%{dag_id: dag.id, params: FamilyRequest.to_params(request)})

    run
  end

  defp start_http_stub! do
    agent = start_supervised!({Agent, fn -> %{comparison_seeds: [], correction_requests: []} end})
    start_stub_server!(agent)
    agent
  end

  defp start_stub_server!(agent) do
    server =
      start_supervised!(
        {Bandit,
         plug: {NetworkDefense.Evaluation.FamilyHTTPStub, agent}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    configure_client!(port)
  end

  # The family member adapter uses the accepted comparison client, so both
  # clients must point at the same stub.
  defp configure_client!(port) do
    clients = [Client, NetworkDefense.Evaluation.Comparison.Client]
    originals = Enum.map(clients, &{&1, Application.fetch_env!(:network_defense, &1)})

    Enum.each(clients, fn client ->
      Application.put_env(:network_defense, client, base_url: "http://127.0.0.1:#{port}")
    end)

    on_exit(fn ->
      Enum.each(originals, fn {client, config} ->
        Application.put_env(:network_defense, client, config)
      end)
    end)
  end

  defp use_immediate_retries! do
    original_delayer = Application.get_env(:gust, :dag_task_delayer)

    Application.put_env(:gust, :dag_task_delayer, NetworkDefense.Evaluation.FamilyImmediateRetry)

    on_exit(fn ->
      if original_delayer do
        Application.put_env(:gust, :dag_task_delayer, original_delayer)
      else
        Application.delete_env(:gust, :dag_task_delayer)
      end
    end)
  end

  defp use_slow_retries! do
    original_delayer = Application.get_env(:gust, :dag_task_delayer)

    Application.put_env(:gust, :dag_task_delayer, NetworkDefense.Evaluation.FamilySlowRetry)

    on_exit(fn ->
      if original_delayer do
        Application.put_env(:gust, :dag_task_delayer, original_delayer)
      else
        Application.delete_env(:gust, :dag_task_delayer)
      end
    end)
  end

  defp wait_for_family_dag! do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case Gust.Flows.get_dag_by_name("evaluation_family") do
        nil ->
          Process.sleep(10)
          {:cont, nil}

        dag ->
          {:halt, dag}
      end
    end) || flunk("Gust did not load evaluation_family")
  end
end
