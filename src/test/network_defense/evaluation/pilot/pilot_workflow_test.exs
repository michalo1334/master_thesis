defmodule NetworkDefense.Evaluation.Pilot.PilotWorkflowTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.ErrorParser
  alias Gust.DAG.Loader.Worker, as: DagLoader
  alias Gust.Flows.Run

  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotRequest, PilotResult}
  alias NetworkDefense.Evaluation.Pilot.{TaskFailure, TaskFailure.RetryableError, Workflow}
  alias NetworkDefense.Evaluation.PilotConformance
  alias NetworkDefense.Evaluations

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    owner = Sandbox.start_owner!(NetworkDefense.Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(owner)
      Sandbox.stop_owner(gust_owner)
    end)

    reset_gust_records!()

    start_supervised!({DagLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})

    assert_pilot_definition_registered!()

    {:ok, dag} =
      Gust.Flows.create_dag(%{name: "evaluation_pilot_#{System.unique_integer([:positive])}"})

    {:ok, snapshot} = Evaluations.create_evidence_snapshot(PilotConformance.snapshot())
    request = PilotConformance.parsed_request(%{"snapshot_id" => snapshot.id})

    %{dag: dag, snapshot: snapshot, request: request}
  end

  test "WORKFLOW-01: an invalid request creates no pilot run", %{snapshot: snapshot} do
    assert %{name: "evaluation_pilot"} = Gust.Flows.get_dag_by_name("evaluation_pilot")

    before_count = Gust.Repo.aggregate(Run, :count)
    assert before_count == 0

    params =
      "invalid/missing-comparison.request.json"
      |> PilotConformance.read()
      |> Map.put("snapshot_id", snapshot.id)

    assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
             Evaluations.submit_pilot(params)

    codes = Enum.map(issues, & &1["code"])
    assert "missing_comparison" in codes
    refute "snapshot_not_found" in codes
    assert Gust.Repo.aggregate(Run, :count) == before_count
  end

  test "WORKFLOW-02: a snapshot that is not stored creates no pilot run", %{snapshot: _snapshot} do
    before_count = Gust.Repo.aggregate(Run, :count)

    params =
      PilotConformance.request_params(Ecto.UUID.generate())

    assert {:error, %PilotError{issues: [issue]}} = Evaluations.submit_pilot(params)
    assert issue["code"] == "snapshot_not_found"
    assert Gust.Repo.aggregate(Run, :count) == before_count
  end

  test "WORKFLOW-03: a declared comparison mismatch creates no pilot run", %{
    snapshot: snapshot
  } do
    before_count = Gust.Repo.aggregate(Run, :count)

    params =
      snapshot.id
      |> PilotConformance.request_params()
      |> put_in(["expected_comparisons", Access.at(1), "budget"], 8)

    assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
             Evaluations.submit_pilot(params)

    assert Enum.any?(issues, &(&1["code"] == "missing_comparison"))
    assert Gust.Repo.aggregate(Run, :count) == before_count
  end

  test "WORKFLOW-04: a stored result reads back through the public boundary", %{
    dag: dag,
    snapshot: snapshot,
    request: request
  } do
    stored = %{PilotConformance.stored_result() | "snapshot_id" => snapshot.id}

    {:ok, run} =
      Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: PilotRequest.to_params(request),
        status: :succeeded
      })

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "select_pilot",
        run_id: run.id,
        status: :succeeded,
        result: stored
      })

    assert {:ok, %PilotResult{} = first} = Workflow.result(run.id)
    assert {:ok, %PilotResult{} = second} = Workflow.result(run.id)
    assert first == second
    assert first.recommendation.candidate_position == 2
  end

  test "WORKFLOW-05: a changed stored result is rejected", %{
    dag: dag,
    snapshot: snapshot,
    request: request
  } do
    stored =
      snapshot.id
      |> then(fn id -> %{PilotConformance.stored_result() | "snapshot_id" => id} end)
      |> put_in(["recommendation", "plan_count"], 5)

    {:ok, run} =
      Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: PilotRequest.to_params(request),
        status: :succeeded
      })

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "select_pilot",
        run_id: run.id,
        status: :succeeded,
        result: stored
      })

    assert {:error, %PilotError{}} = Workflow.result(run.id)
  end

  test "WORKFLOW-09: a reversed stored row order is rejected on read-back", %{
    dag: dag,
    snapshot: snapshot,
    request: request
  } do
    stored =
      snapshot.id
      |> then(fn id -> %{PilotConformance.stored_result() | "snapshot_id" => id} end)
      |> Map.update!("candidate_results", &Enum.reverse/1)

    {:ok, run} =
      Gust.Flows.create_run(%{
        dag_id: dag.id,
        params: PilotRequest.to_params(request),
        status: :succeeded
      })

    {:ok, _task} =
      Gust.Flows.create_task(%{
        name: "select_pilot",
        run_id: run.id,
        status: :succeeded,
        result: stored
      })

    assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
             Evaluations.get_pilot_result(run.id)

    assert Enum.any?(issues, &(&1["code"] == "changed_candidate_result"))
  end

  test "WORKFLOW-06: waiting reports timeout and readiness explicitly", %{dag: dag} do
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: %{}})

    assert {:error, :not_ready} = Workflow.result(run.id)
    assert {:error, :timeout} = Workflow.await(run.id, 0)
    assert {:error, :not_found} = Workflow.result(-1)
  end

  test "WORKFLOW-07: failed runs decode the originating pilot error", %{dag: dag} do
    {:ok, run} = Gust.Flows.create_run(%{dag_id: dag.id, params: %{}, status: :failed})

    {:ok, _upstream} =
      Gust.Flows.create_task(%{name: "prepare_pilot", run_id: run.id, status: :upstream_failed})

    typed = PilotError.unavailable()
    exception = assert_raise(RetryableError, fn -> TaskFailure.raise_retryable(typed) end)

    {:ok, _failed} =
      Gust.Flows.create_task(%{
        name: "evaluate_candidate_comparison",
        run_id: run.id,
        status: :failed,
        attempt: 3,
        error: exception |> ErrorParser.parse() |> stringify()
      })

    assert {:error, %PilotError{code: "compute_unavailable"}} = Workflow.result(run.id)
  end

  test "WORKFLOW-08: a pilot error envelope never decodes as another workflow error" do
    assert :error =
             TaskFailure.decode(%{
               "type" => "Gust.DAG.NonRecError",
               "message" => String.duplicate("x", 65_537)
             })

    assert :error = TaskFailure.decode(%{"type" => "unknown", "message" => "{}"})

    family = %{
      "kind" => "network_defense.evaluation.family_error",
      "version" => 1,
      "error" => %{"schema_version" => 1, "error" => %{"code" => "validation_failed"}}
    }

    assert :error =
             TaskFailure.decode(%{
               "type" => "Gust.DAG.NonRecError",
               "message" => Jason.encode!(family)
             })
  end

  defp reset_gust_records! do
    # Delete committed DAG, run, and task rows inside this test transaction.
    # The loader then creates every DAG again, so no case can depend on a DAG
    # or a run that another process left in the test database. The sandbox
    # rollback restores the deleted rows after the test.
    Gust.Repo.query!("delete from gust_dags")
  end

  defp assert_pilot_definition_registered! do
    # `get_definitions/0` is a synchronous call. The worker loads the DAG
    # folder in its `:bootstrap` continuation, which runs before the worker
    # handles any message, so this call returns only after registration.
    definitions = DagLoader.get_definitions()

    %{id: pilot_dag_id, name: "evaluation_pilot"} =
      Gust.Flows.get_dag_by_name("evaluation_pilot") ||
        flunk("Gust did not register evaluation_pilot")

    assert {:ok, _definition} = Map.fetch!(definitions, pilot_dag_id)
  end

  defp stringify(value), do: value |> Jason.encode!() |> Jason.decode!()
end
