defmodule NetworkDefense.Evaluation.ComparisonHTTPStub do
  @moduledoc false

  import Plug.Conn

  def init(agent), do: agent

  def call(conn, agent) do
    {:ok, _body, conn} = read_body(conn)

    {status, body} =
      Agent.get_and_update(agent, fn state ->
        case state.responses do
          [response | rest] ->
            {response, %{state | responses: rest, last: response, count: state.count + 1}}

          [] ->
            {state.last, %{state | count: state.count + 1}}
        end
      end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end

defmodule NetworkDefense.Evaluation.ComparisonImmediateRetry do
  @moduledoc false
  @behaviour Gust.DAG.TaskDelayer

  @impl true
  def calc_delay(_attempt), do: 0
end

defmodule NetworkDefense.Evaluation.ComparisonGustIntegrationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Run.Trigger
  alias NetworkDefense.Evaluation.Comparison.Actions.Compare
  alias NetworkDefense.Evaluation.Comparison.{Client, TaskFailure}
  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonError, ComparisonStatistics}
  alias NetworkDefense.Evaluations

  @contracts_root Path.expand("../../../../contracts/evaluation/comparison/v1", __DIR__)

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    start_supervised!(
      {Gust.DAG.Loader.Worker, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}}
    )

    start_supervised!({Gust.Run.DispatcherSupervisor, []})

    dag = wait_for_dag!()
    %{dag: dag}
  end

  test "GUST-E2E-01: real DAG stores the native HTTP result", %{dag: _dag} do
    statistics = read_json("valid/informative.statistics.json")
    {agent, _server} = start_http_stub!(200, statistics)
    request = read_json("valid/crossed-small.request.json")

    assert {:ok, run_id} = Evaluations.submit_comparison(request)
    assert {:ok, :succeeded} = Evaluations.await_comparison(run_id, 5_000)

    assert {:ok, %ComparisonStatistics{estimate: %{"value" => -1.42}}} =
             Evaluations.get_comparison_result(run_id)

    run = Gust.Flows.get_run_with_tasks!(run_id)
    compare = Enum.find(run.tasks, &(&1.name == "compare"))
    assert compare.status == :succeeded
    assert compare.result == statistics
    assert Agent.get(agent, & &1.count) == 1
  end

  test "GUST-E2E-02: Compare uses its explicit request instead of root run params", %{dag: dag} do
    invalid_root = read_json("invalid/attack-column-count-mismatch.request.json")
    explicit_request = read_json("valid/crossed-small.request.json")
    statistics = read_json("valid/informative.statistics.json")
    {_agent, _server} = start_http_stub!(200, statistics)
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: invalid_root})

    assert Compare.execute([request: explicit_request], %{run_id: run.id}) == statistics
  end

  test "GUST-E2E-03: temporary HTTP failure retries and stores the later success", %{dag: _dag} do
    use_immediate_retries!()
    error = unavailable_error()
    statistics = read_json("valid/informative.statistics.json")
    {agent, _server} = start_http_sequence!([{503, error}, {200, statistics}])
    request = read_json("valid/crossed-small.request.json")

    assert {:ok, run_id} = Evaluations.submit_comparison(request)
    assert {:ok, :succeeded} = Evaluations.await_comparison(run_id, 5_000)

    persisted = Gust.Flows.get_run_with_tasks!(run_id)
    compare = Enum.find(persisted.tasks, &(&1.name == "compare"))
    assert compare.status == :succeeded
    assert compare.attempt == 2
    assert compare.result == statistics
    assert compare.error == %{}
    assert Agent.get(agent, & &1.count) == 2
  end

  test "GUST-E2E-04: prepare failure is permanent and blocks compare", %{dag: dag} do
    invalid = read_json("invalid/attack-column-count-mismatch.request.json")
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: invalid})
    dispatched = Trigger.dispatch_run(run)

    assert {:error, %ComparisonError{code: "validation_failed"}} =
             Evaluations.await_comparison(dispatched.id, 5_000)

    persisted = Gust.Flows.get_run_with_tasks!(dispatched.id)
    prepare = Enum.find(persisted.tasks, &(&1.name == "prepare"))
    compare = Enum.find(persisted.tasks, &(&1.name == "compare"))
    assert prepare.status == :failed
    assert prepare.attempt == 1
    assert prepare.result == %{}
    assert prepare.error["type"] == "Gust.DAG.NonRecError"

    assert {:ok, %ComparisonError{code: "validation_failed", issues: [issue]}} =
             TaskFailure.decode(prepare.error)

    assert issue["code"] == "attack_column_count_mismatch"
    assert issue["path"] == ["evidence", "alternative", "plans", 0, "mission_impacts"]
    assert issue["details"] == %{"actual" => 9, "expected" => 10}
    assert compare.status == :upstream_failed
    assert compare.result == %{}
  end

  test "GUST-E2E-05: retryable HTTP failures exhaust three attempts", %{dag: _dag} do
    use_immediate_retries!()
    error = unavailable_error()

    {agent, _server} = start_http_stub!(503, error)
    request = read_json("valid/crossed-small.request.json")

    assert {:ok, run_id} = Evaluations.submit_comparison(request)

    assert {:error, %ComparisonError{code: "compute_unavailable"}} =
             Evaluations.await_comparison(run_id, 5_000)

    persisted = Gust.Flows.get_run_with_tasks!(run_id)
    compare = Enum.find(persisted.tasks, &(&1.name == "compare"))
    assert compare.status == :failed
    assert compare.attempt == 3
    assert compare.result == %{}
    assert compare.error["type"] == "Gust.DAG.NonRecError"

    assert {:ok, %ComparisonError{code: "compute_unavailable", issues: [issue]}} =
             TaskFailure.decode(compare.error)

    assert issue["code"] == "compute_unavailable"
    assert issue["path"] == []
    assert issue["details"] == %{}
    assert Agent.get(agent, & &1.count) == 3
  end

  defp start_http_stub!(status, body), do: start_http_sequence!([{status, body}])

  defp start_http_sequence!(responses) do
    agent =
      start_supervised!({Agent, fn -> %{responses: responses, last: hd(responses), count: 0} end})

    server =
      start_supervised!(
        {Bandit,
         plug: {NetworkDefense.Evaluation.ComparisonHTTPStub, agent}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    original_client = Application.fetch_env!(:network_defense, Client)
    Application.put_env(:network_defense, Client, base_url: "http://127.0.0.1:#{port}")
    on_exit(fn -> Application.put_env(:network_defense, Client, original_client) end)
    {agent, server}
  end

  defp use_immediate_retries! do
    original_delayer = Application.get_env(:gust, :dag_task_delayer)

    Application.put_env(
      :gust,
      :dag_task_delayer,
      NetworkDefense.Evaluation.ComparisonImmediateRetry
    )

    on_exit(fn ->
      if original_delayer do
        Application.put_env(:gust, :dag_task_delayer, original_delayer)
      else
        Application.delete_env(:gust, :dag_task_delayer)
      end
    end)
  end

  defp unavailable_error do
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
    }
  end

  defp wait_for_dag! do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case Gust.Flows.get_dag_by_name("evaluation_comparison") do
        nil ->
          Process.sleep(10)
          {:cont, nil}

        dag ->
          {:halt, dag}
      end
    end) || flunk("Gust did not load evaluation_comparison")
  end

  defp read_json(relative_path) do
    @contracts_root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()
  end
end
