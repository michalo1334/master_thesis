defmodule NetworkDefense.Evaluation.Family.FamilyWorkflowTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.Flows.Run

  alias NetworkDefense.Evaluation.Family.Actions.Prepare
  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, FamilyRequest, FamilyResult}
  alias NetworkDefense.Evaluation.Family.{TaskFailure, Workflow}
  alias NetworkDefense.Evaluation.Family.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.FamilyConformance
  alias NetworkDefense.Evaluations

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    name = "evaluation_family_test_#{System.unique_integer([:positive])}"
    {:ok, dag} = Gust.Flows.create_dag(%{name: name, enabled: true})

    %{dag: dag}
  end

  test "WORKFLOW-01: public validation creates no family run" do
    before_count = Gust.Repo.aggregate(Run, :count)
    invalid = FamilyConformance.read("invalid/missing-comparison.request.json")

    assert {:error, %FamilyError{code: "validation_failed", issues: [_ | _]}} =
             Evaluations.submit_family(invalid)

    assert Gust.Repo.aggregate(Run, :count) == before_count
  end

  test "WORKFLOW-02: prepare permanently rejects invalid persisted parameters", %{dag: dag} do
    invalid = FamilyConformance.read("invalid/duplicate-expected-identity.request.json")
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: invalid})
    {:ok, task} = Gust.Flows.create_task(%{name: "prepare_family", run_id: run.id})

    exception = assert_raise(NonRecError, fn -> Prepare.execute([], %{run_id: run.id}) end)

    persisted_error = exception |> ErrorParser.parse() |> stringify()
    {:ok, failed_task} = Gust.Flows.update_task_result_error(task, %{}, persisted_error)
    {:ok, failed_task} = Gust.Flows.update_task_status(failed_task, :failed)

    assert {:ok, %FamilyError{} = error} = TaskFailure.decode(failed_task.error)
    assert error.code == "validation_failed"
    assert Enum.any?(error.issues, &(&1["code"] == "duplicate_expected_identity"))
  end

  test "WORKFLOW-03: a stored family result loads through the native Gust lookup", %{dag: dag} do
    request = family_request!()
    params = family_result_params!(request)

    {:ok, run} =
      Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: FamilyRequest.to_params(request),
        status: :succeeded
      })

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "correct_family",
        run_id: run.id,
        status: :succeeded,
        result: params
      })

    assert {:ok, %FamilyResult{} = stored} = Workflow.result(run.id)
    assert stored.family_size == 4

    assert Enum.map(stored.comparisons, & &1.adjustment.adjusted_p_value) ==
             FamilyConformance.adjusted_p_values()
  end

  test "WORKFLOW-04: a stored result that no longer matches the request is rejected", %{dag: dag} do
    request = family_request!()

    params =
      request
      |> family_result_params!()
      |> update_in(["comparisons", Access.at(0), "adjustment", "reject_null"], fn _ -> false end)

    {:ok, run} =
      Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: FamilyRequest.to_params(request),
        status: :succeeded
      })

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "correct_family",
        run_id: run.id,
        status: :succeeded,
        result: params
      })

    assert {:error, %FamilyError{code: "invalid_response_contract"}} = Workflow.result(run.id)
  end

  test "WORKFLOW-05: failed runs decode the originating family error", %{dag: dag} do
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: %{}, status: :failed})

    {:ok, _upstream} =
      Gust.Flows.create_task(%{name: "compare_member", run_id: run.id, status: :upstream_failed})

    typed = FamilyError.unavailable()

    exception = assert_raise(RetryableError, fn -> TaskFailure.raise_retryable(typed) end)

    {:ok, _failed} =
      Gust.Flows.create_task(%{
        name: "correct_family",
        run_id: run.id,
        status: :failed,
        attempt: 3,
        error: exception |> ErrorParser.parse() |> stringify()
      })

    assert {:error, %FamilyError{code: "compute_unavailable"}} = Workflow.result(run.id)
  end

  test "WORKFLOW-06: waiting reports timeout and readiness explicitly", %{dag: dag} do
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: %{}})

    assert {:error, :not_ready} = Workflow.result(run.id)
    assert {:error, :timeout} = Workflow.await(run.id, 0)
    assert {:error, :not_found} = Workflow.result(-1)
  end

  test "WORKFLOW-07: a succeeded run without a stored correction result is rejected", %{dag: dag} do
    request = family_request!()

    {:ok, run} =
      Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: FamilyRequest.to_params(request),
        status: :succeeded
      })

    assert {:error, %FamilyError{code: "invalid_response_contract"}} = Workflow.result(run.id)
  end

  test "GUST-05: a family error envelope never decodes as a comparison error" do
    persisted = %{
      "type" => "Gust.DAG.NonRecError",
      "message" => String.duplicate("x", 65_537)
    }

    assert :error = TaskFailure.decode(persisted)
    assert :error = TaskFailure.decode(%{"type" => "unknown", "message" => "{}"})
  end

  defp family_request!, do: FamilyConformance.parsed_request()

  # The stored example is a checked-in conformance file. Elixir must read the
  # same bytes that Python produced.
  defp family_result_params!(%FamilyRequest{}), do: FamilyConformance.stored_result()

  defp stringify(value), do: value |> Jason.encode!() |> Jason.decode!()
end
