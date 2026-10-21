defmodule NetworkDefense.Evaluation.Final.GustIntegrationTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Run.Trigger
  alias Gust.Flows

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Result}
  alias NetworkDefense.Evaluation.FinalComputeStub
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluations
  alias NetworkDefense.Repo

  # Acceptance coverage in this file:
  #   S5-01  one typed Final snapshot is created and read back
  #   S5-02  a missing snapshot rejects before Gust run creation
  #   S5-03  a missing or non-recommended Pilot source rejects
  #   S5-04  copied counts must equal the Pilot recommendation
  #   S5-05  preparation stops a run before mapped work
  #   S5-07  declared order survives any completion order
  #   S5-09  read-back validates stored relations
  #   S5-10  assertions stay labelled as caller-asserted data
  #   S5-11  a repeat submission starts another run

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    owner = Sandbox.start_owner!(Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(owner)
      Sandbox.stop_owner(gust_owner)
    end)

    :ok = FinalComputeStub.start_gust!()

    agent = FinalComputeStub.start!()
    pilot_run_id = FinalComputeStub.recommended_pilot_run!()

    assert {:ok, snapshot} =
             Evaluations.create_final_evidence_snapshot(FinalConformance.snapshot())

    params = FinalConformance.request_params!(snapshot.id, pilot_run_id)

    %{agent: agent, pilot_run_id: pilot_run_id, snapshot: snapshot, params: params}
  end

  test "E2E-01: the complete Final family is corrected once in declared order", %{
    agent: agent,
    snapshot: snapshot,
    params: params
  } do
    assert {:ok, stored} = Evaluations.get_final_evidence_snapshot(snapshot.id)
    assert stored.phase == :final
    assert stored.family_id == "family-example"
    assert stored == snapshot

    assert {:ok, run_id} = Evaluations.submit_final(params)
    assert {:ok, :succeeded} = Evaluations.await_final(run_id, 20_000)
    assert {:ok, %Result{} = result} = Evaluations.get_final_result(run_id)

    assert result.evidence_role == "final"
    assert result.method == "holm"
    assert result.family_size == 2
    assert result.assertion_basis == "caller_asserted"
    assert result.snapshot_id == snapshot.id
    assert result.plan_count == 6
    assert result.attacks_per_plan == 10

    assert Enum.map(result.comparisons, &Identity.key(&1.identity)) ==
             Enum.map(FinalConformance.snapshot()["payload"]["comparisons"], fn comparison ->
               identity = comparison["identity"]

               {identity["tier"], identity["budget"], identity["alternative"],
                identity["reference"], identity["outcome"]}
             end)

    assert Enum.map(result.comparisons, & &1.statistics.test["raw_p_value"]) ==
             FinalConformance.raw_p_values()

    assert Enum.map(result.comparisons, & &1.adjustment.adjusted_p_value) ==
             Enum.map(FinalConformance.correction_response()["results"], & &1["adjusted_p_value"])

    assert Enum.all?(result.comparisons, & &1.adjustment.reject_null)

    state = Agent.get(agent, & &1)
    assert Enum.sort(state.comparison_seeds) == Enum.sort(params["comparison_seeds"])
    assert [correction] = state.correction_requests

    assert correction["raw_results"]
           |> Enum.map(& &1["raw_p_value"]) == FinalConformance.raw_p_values()

    refute Map.has_key?(correction, "evidence")
    assert correction["alpha"] == 0.05

    # No evidence matrix reaches Gust: the stored run and the mapped items stay
    # compact, and the statistics are the only computed payload.
    persisted = Flows.get_run_with_tasks!(run_id)
    refute Map.has_key?(persisted.params, "payload")
    refute Map.has_key?(persisted.params, "evidence")

    items =
      persisted.tasks
      |> Enum.find(&(&1.name == "prepare_final"))
      |> Map.fetch!(:result)
      |> Map.fetch!("gust_task_items")

    assert Enum.map(items, &Map.keys(&1)) == [["identity", "position"], ["identity", "position"]]
  end

  test "E2E-02: declared order survives a reversed completion order", %{
    agent: agent,
    params: params
  } do
    [first_seed | _rest] = params["comparison_seeds"]
    FinalComputeStub.slow!(agent, first_seed, 400)

    assert {:ok, run_id} = Evaluations.submit_final(params)
    assert {:ok, :succeeded} = Evaluations.await_final(run_id, 20_000)
    assert {:ok, %Result{} = result} = Evaluations.get_final_result(run_id)

    assert Enum.map(result.comparisons, & &1.identity.tier) == ["core", "edge"]

    assert Agent.get(agent, & &1.completion_order)
           |> Enum.reverse() != params["comparison_seeds"]
  end

  test "E2E-03: a missing snapshot rejects before Gust run creation", %{params: params} do
    before_count = count_final_runs()

    unknown = Map.put(params, "snapshot_id", "11111111-2222-3333-4444-555555555555")

    assert {:error, %FinalError{} = error} = Evaluations.submit_final(unknown)
    assert Enum.any?(error.issues, &(&1["code"] == "snapshot_not_found"))
    assert count_final_runs() == before_count
  end

  test "E2E-04: a missing or secondary Pilot source rejects without a run", %{params: params} do
    before_count = count_final_runs()

    unknown_pilot = Map.put(params, "source_pilot_run_id", 999_999)

    assert {:error, %FinalError{} = error} = Evaluations.submit_final(unknown_pilot)
    assert Enum.any?(error.issues, &(&1["code"] == "pilot_not_found"))

    # A comparison run is not a Pilot run, so it cannot supply Final counts.
    [comparison_request | _rest] = FinalConformance.member_requests!()

    assert {:ok, comparison_run_id} = Evaluations.submit_comparison(comparison_request)
    assert {:ok, :succeeded} = Evaluations.await_comparison(comparison_run_id, 20_000)

    wrong_source = Map.put(params, "source_pilot_run_id", comparison_run_id)
    assert {:error, %FinalError{}} = Evaluations.submit_final(wrong_source)
    assert count_final_runs() == before_count
  end

  test "E2E-05: a count override rejects the request", %{params: params} do
    before_count = count_final_runs()

    # An overridden count contradicts the stored evidence, so the snapshot
    # correlation rejects it before the Pilot recommendation is consulted.
    assert {:error, %FinalError{} = error} =
             Evaluations.submit_final(Map.put(params, "plan_count", 7))

    assert Enum.any?(error.issues, &(&1["code"] == "plan_count_mismatch"))

    assert {:error, %FinalError{} = error} =
             Evaluations.submit_final(
               Map.put(params, "comparison_seeds", Enum.take(params["comparison_seeds"], 1))
             )

    assert Enum.any?(error.issues, &(&1["code"] == "seed_count_mismatch"))
    assert count_final_runs() == before_count
  end

  test "E2E-06: preparation stops the run before any mapped comparison", %{
    agent: agent,
    snapshot: snapshot,
    params: params
  } do
    dag = Flows.get_dag_by_name("evaluation_final")

    {:ok, run} =
      Flows.create_run(%{dag_id: dag.id, params: Map.put(params, "snapshot_id", snapshot.id)})

    # Change the stored evidence after the run was created, before preparation
    # reads it. The stored byte count no longer matches, so preparation stops.
    tamper_payload!(snapshot.id)

    dispatched = Trigger.dispatch_run(run)

    assert {:error, %FinalError{} = error} = Evaluations.await_final(dispatched.id, 20_000)

    assert error.code in ["validation_failed", "workflow_failed", "invalid_response_contract"]

    persisted = Flows.get_run_with_tasks!(dispatched.id)
    assert persisted.status == :failed

    refute Enum.any?(
             persisted.tasks,
             &(&1.name == "compare_final_member" and &1.status == :succeeded)
           )

    assert Agent.get(agent, & &1.comparison_seeds) == []
  end

  test "E2E-07: a tampered stored result is rejected on read-back", %{params: params} do
    assert {:ok, run_id} = Evaluations.submit_final(params)
    assert {:ok, :succeeded} = Evaluations.await_final(run_id, 20_000)
    assert {:ok, %Result{}} = Evaluations.get_final_result(run_id)

    swap_first_comparison_identity!(run_id)

    assert {:error, %FinalError{} = error} = Evaluations.get_final_result(run_id)
    assert error.code in ["invalid_response_contract", "validation_failed"]
  end

  test "E2E-08: the same request can start a second run", %{params: params} do
    assert {:ok, first_run_id} = Evaluations.submit_final(params)
    assert {:ok, :succeeded} = Evaluations.await_final(first_run_id, 20_000)

    assert {:ok, second_run_id} = Evaluations.submit_final(params)
    assert second_run_id != first_run_id
    assert {:ok, :succeeded} = Evaluations.await_final(second_run_id, 20_000)

    assert {:ok, %Result{} = first} = Evaluations.get_final_result(first_run_id)
    assert {:ok, %Result{} = second} = Evaluations.get_final_result(second_run_id)
    assert first == second
  end

  test "E2E-09: a temporary correction outage retries only the correction", %{
    agent: agent,
    params: params
  } do
    # The first Holm call fails with a documented temporary status. The members
    # already succeeded, so Gust must retry the fan-in alone.
    FinalComputeStub.fail_correction!(agent, 503, "compute_unavailable")

    assert {:ok, run_id} = Evaluations.submit_final(params)
    assert {:ok, :succeeded} = Evaluations.await_final(run_id, 60_000)
    assert {:ok, %Result{} = result} = Evaluations.get_final_result(run_id)

    state = Agent.get(agent, & &1)

    # Each declared seed reached the comparison endpoint exactly once.
    assert Enum.sort(state.comparison_seeds) == Enum.sort(params["comparison_seeds"])
    assert Enum.count(state.comparison_seeds) == 2

    # The correction was attempted twice: the failed call and the retry.
    assert Enum.count(state.correction_requests) == 2
    assert Enum.uniq(state.correction_requests) == [FinalConformance.correction_request()]

    # The seeds, the order, and the numerical answers are unchanged.
    assert Enum.map(result.comparisons, & &1.statistics.test["raw_p_value"]) ==
             FinalConformance.raw_p_values()

    assert Enum.map(result.comparisons, & &1.adjustment.adjusted_p_value) ==
             Enum.map(FinalConformance.correction_response()["results"], & &1["adjusted_p_value"])
  end

  test "E2E-10: an exhausted temporary outage decodes as a bounded Final failure", %{
    agent: agent,
    params: params
  } do
    # Gust retries a fixed number of times. Every attempt fails, so the run must
    # end with a decodable Final failure and no stored result.
    Enum.each(1..10, fn _attempt ->
      FinalComputeStub.fail_correction!(agent, 503, "compute_unavailable")
    end)

    assert {:ok, run_id} = Evaluations.submit_final(params)

    assert {:error, %FinalError{} = error} = Evaluations.await_final(run_id, 120_000)
    assert error.code in ["compute_unavailable", "compute_failed", "workflow_failed"]

    assert {:error, %FinalError{}} = Evaluations.get_final_result(run_id)
    assert Enum.count(Agent.get(agent, & &1.comparison_seeds)) == 2
  end

  defp count_final_runs do
    dag = Flows.get_dag_by_name("evaluation_final")
    Flows.count_runs_on_dag(dag.id)
  end

  defp tamper_payload!(snapshot_id) do
    payload = FinalConformance.snapshot()["payload"]
    changed = %{payload | "comparisons" => Enum.reverse(payload["comparisons"])}

    {_count, _rows} =
      Repo.update_all(from(snapshot in EvidenceSnapshot, where: snapshot.id == ^snapshot_id),
        set: [payload: changed]
      )
  end

  defp swap_first_comparison_identity!(run_id) do
    task =
      Gust.Repo.one(
        from(task in Gust.Flows.Task,
          where: task.run_id == ^run_id and task.name == "correct_final_family"
        )
      )

    [first, second | rest] = task.result["comparisons"]

    tampered = %{
      task.result
      | "comparisons" => [%{first | "identity" => second["identity"]}, second | rest]
    }

    {:ok, _task} = Flows.update_task_result(task, tampered)
  end
end
