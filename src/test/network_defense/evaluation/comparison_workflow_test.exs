defmodule NetworkDefense.Evaluation.ComparisonWorkflowTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.Flows.Run
  alias NetworkDefense.Evaluation.Comparison.Actions.Prepare
  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonError, ComparisonStatistics}
  alias NetworkDefense.Evaluation.Comparison.{TaskFailure, Workflow}
  alias NetworkDefense.Evaluation.Comparison.TaskFailure.RetryableError
  alias NetworkDefense.Evaluations

  @contracts_root Path.expand("../../../../contracts/evaluation/comparison/v1", __DIR__)

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    name = "evaluation_test_#{System.unique_integer([:positive])}"
    {:ok, dag} = Gust.Flows.create_dag(%{name: name, enabled: true})

    %{dag: dag}
  end

  test "WORKFLOW-02: public validation creates no Gust run", %{dag: _dag} do
    before_count = Gust.Repo.aggregate(Run, :count)
    invalid = read_json("invalid/attack-column-count-mismatch.request.json")

    assert {:error, %ComparisonError{code: "validation_failed"}} =
             Evaluations.submit_comparison(invalid)

    assert Gust.Repo.aggregate(Run, :count) == before_count
  end

  test "WORKFLOW-03: prepare permanently rejects directly persisted invalid input", %{dag: dag} do
    invalid = read_json("invalid/attack-column-count-mismatch.request.json")
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: invalid})
    {:ok, task} = Gust.Flows.create_task(%{name: "prepare", run_id: run.id})

    exception =
      assert_raise NonRecError, fn -> Prepare.execute([], %{run_id: run.id}) end

    persisted_error = ErrorParser.parse(exception) |> stringify()
    {:ok, failed_task} = Gust.Flows.update_task_result_error(task, %{}, persisted_error)
    {:ok, failed_task} = Gust.Flows.update_task_status(failed_task, :failed)

    assert failed_task.attempt == 1
    assert failed_task.result == %{}
    assert {:ok, error} = TaskFailure.decode(failed_task.error)
    assert hd(error.issues)["code"] == "attack_column_count_mismatch"
  end

  test "WORKFLOW-04: successful stored compare result loads through native Gust lookup", %{
    dag: dag
  } do
    request = read_json("valid/crossed-small.request.json")
    statistics = read_json("valid/informative.statistics.json")
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: request, status: :succeeded})

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "compare",
        run_id: run.id,
        status: :succeeded,
        result: statistics
      })

    assert {:ok, %ComparisonStatistics{} = stored} = Workflow.result(run.id)
    assert stored.estimate["value"] == -1.42
  end

  test "WORKFLOW-05: failed runs decode the originating typed error", %{dag: dag} do
    request = read_json("valid/crossed-small.request.json")
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: request, status: :failed})

    {:ok, _upstream} =
      Gust.Flows.create_task(%{name: "later", run_id: run.id, status: :upstream_failed})

    typed =
      ComparisonError.new(
        "compute_unavailable",
        "compute_unavailable",
        [],
        "The compute service is unavailable."
      )

    exception =
      assert_raise RetryableError, fn ->
        TaskFailure.raise_retryable(typed)
      end

    {:ok, _failed} =
      Gust.Flows.create_task(%{
        name: "compare",
        run_id: run.id,
        status: :failed,
        attempt: 3,
        error: exception |> ErrorParser.parse() |> stringify()
      })

    assert %ComparisonError{code: "compute_unavailable"} = Workflow.failure_for_run(run.id)
    assert {:error, %ComparisonError{code: "compute_unavailable"}} = Workflow.result(run.id)
  end

  test "WORKFLOW-06: a successful retry clears the old error", %{dag: dag} do
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: %{}})

    {:ok, task} =
      Gust.Flows.create_task(%{
        name: "compare",
        run_id: run.id,
        status: :retrying,
        attempt: 2,
        error: %{"type" => "temporary", "message" => "safe"}
      })

    {:ok, task} = Gust.Flows.update_task_result_error(task, %{"ok" => true}, %{})
    {:ok, task} = Gust.Flows.update_task_status(task, :succeeded)
    assert task.result == %{"ok" => true}
    assert task.error == %{}
  end

  test "REL-03: stored results with invalid relations are rejected", %{dag: dag} do
    request = read_json("valid/crossed-small.request.json")

    statistics =
      "valid/informative.statistics.json"
      |> read_json()
      |> put_in(["interval", "lower"], 10.0)
      |> put_in(["interval", "upper"], -10.0)

    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: request, status: :succeeded})

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "compare",
        run_id: run.id,
        status: :succeeded,
        result: statistics
      })

    assert {:error, %ComparisonError{code: "invalid_response_contract"}} =
             Workflow.result(run.id)
  end

  test "GUST-05: oversized persisted failures are rejected safely", %{dag: _dag} do
    persisted = %{
      "type" => "Gust.DAG.NonRecError",
      "message" => String.duplicate("x", 65_537)
    }

    assert :error = TaskFailure.decode(persisted)
  end

  defp read_json(relative_path) do
    @contracts_root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()
  end

  defp stringify(value), do: value |> Jason.encode!() |> Jason.decode!()
end
