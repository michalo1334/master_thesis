defmodule NetworkDefense.Evaluation.Final.BindingTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.Flows

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Final.Actions.{CompareFinalMember, CorrectFinalFamily}
  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}
  alias NetworkDefense.Evaluation.Final.{Member, TaskFailure}
  alias NetworkDefense.Evaluation.FinalComputeStub
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluations
  alias NetworkDefense.Repo

  # Acceptance coverage in this file:
  #   S5-05  a snapshot or source that changed after preparation stops the run
  #   S5-09  read-back validates the stored snapshot and source relations
  #
  # Review finding P1 (late-boundary source correlation): submission and
  # preparation check the snapshot metadata and the actual source Pilot. Every
  # later boundary repeats those checks, so a metadata-only snapshot change or a
  # Pilot that stopped being recommended cannot pass a member, the fan-in, or the
  # public result read.

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

  describe "persisted task boundaries" do
    test "BIND-01: a metadata-only snapshot change stops a member before compute", %{
      agent: agent,
      snapshot: snapshot,
      params: params
    } do
      run = crafted_run!(params)
      move_family!(snapshot.id, "family-other")

      exception =
        assert_raise(NonRecError, fn ->
          CompareFinalMember.execute([item: member_item!(params, 0)], %{run_id: run.id})
        end)

      assert "changed_snapshot" in issue_codes(exception)
      assert FinalComputeStub.requests(agent, :comparison_seeds) == []
    end

    test "BIND-02: a metadata-only study change stops the fan-in before the correction", %{
      agent: agent,
      snapshot: snapshot,
      params: params
    } do
      run = crafted_run!(params)
      move_study!(snapshot.id, "8f14e45f-ceea-467f-a831-9dbfe8dd0a11")

      exception =
        assert_raise(NonRecError, fn -> CorrectFinalFamily.execute([], %{run_id: run.id}) end)

      assert "changed_snapshot" in issue_codes(exception)
      assert FinalComputeStub.requests(agent, :correction_requests) == []
    end

    test "BIND-03: a source Pilot that stopped being recommended stops a member", %{
      agent: agent,
      pilot_run_id: pilot_run_id,
      params: params
    } do
      run = crafted_run!(params)
      invalidate_pilot!(pilot_run_id)

      exception =
        assert_raise(NonRecError, fn ->
          CompareFinalMember.execute([item: member_item!(params, 0)], %{run_id: run.id})
        end)

      assert issue_codes(exception) != []
      assert FinalComputeStub.requests(agent, :comparison_seeds) == []
    end

    test "BIND-04: a source Pilot that stopped being recommended stops the fan-in", %{
      agent: agent,
      pilot_run_id: pilot_run_id,
      params: params
    } do
      run = crafted_run!(params)
      invalidate_pilot!(pilot_run_id)

      exception =
        assert_raise(NonRecError, fn -> CorrectFinalFamily.execute([], %{run_id: run.id}) end)

      assert issue_codes(exception) != []
      assert FinalComputeStub.requests(agent, :correction_requests) == []
    end
  end

  describe "public result read" do
    test "BIND-05: a metadata-only snapshot change after success makes the result unreadable", %{
      snapshot: snapshot,
      params: params
    } do
      run_id = succeeded_run!(params)

      assert {:ok, _result} = Evaluations.get_final_result(run_id)

      move_family!(snapshot.id, "family-other")

      assert {:error, error} = Evaluations.get_final_result(run_id)
      assert "changed_snapshot" in issue_codes(error)
    end

    test "BIND-06: a metadata-only study change after success makes the result unreadable", %{
      snapshot: snapshot,
      params: params
    } do
      run_id = succeeded_run!(params)
      move_study!(snapshot.id, "8f14e45f-ceea-467f-a831-9dbfe8dd0a11")

      assert {:error, error} = Evaluations.get_final_result(run_id)
      assert "changed_snapshot" in issue_codes(error)
    end

    test "BIND-07: an invalidated source Pilot after success makes the result unreadable", %{
      pilot_run_id: pilot_run_id,
      params: params
    } do
      run_id = succeeded_run!(params)
      invalidate_pilot!(pilot_run_id)

      assert {:error, error} = Evaluations.get_final_result(run_id)
      assert issue_codes(error) != []
    end
  end

  defp succeeded_run!(params) do
    assert {:ok, run_id} = Evaluations.submit_final(params)
    assert {:ok, :succeeded} = Evaluations.await_final(run_id, 20_000)
    run_id
  end

  # A run that exists but has no task rows yet: the boundaries under test load
  # the persisted request and must reject before they look for member results.
  defp crafted_run!(params) do
    {:ok, dag} =
      Flows.create_dag(%{name: "evaluation_final_binding_#{System.unique_integer([:positive])}"})

    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: params})
    run
  end

  defp member_item!(params, position) do
    {:ok, request} = Request.parse(params)
    Enum.at(Member.declared_items(request), position)
  end

  # A schema-valid metadata-only change: the family identifier stays a string
  # that satisfies the column and the payload still parses.
  defp move_family!(snapshot_id, family_id) do
    {_count, _rows} =
      Repo.update_all(from(snapshot in EvidenceSnapshot, where: snapshot.id == ^snapshot_id),
        set: [family_id: family_id]
      )
  end

  # A second schema-valid metadata-only change. The UUID stays castable and the
  # payload is untouched, so only the cross-record relation breaks.
  defp move_study!(snapshot_id, study_revision_id) do
    {_count, _rows} =
      Repo.update_all(from(snapshot in EvidenceSnapshot, where: snapshot.id == ^snapshot_id),
        set: [study_revision_id: study_revision_id]
      )
  end

  # Replace the stored Pilot selection outcome. The Pilot run still exists, but
  # it no longer reports a recommendation.
  defp invalidate_pilot!(pilot_run_id) do
    task =
      Gust.Repo.one!(
        from(task in Gust.Flows.Task,
          where: task.run_id == ^pilot_run_id and task.name == "select_pilot"
        )
      )

    {:ok, _task} = Flows.update_task_result(task, %{task.result | "outcome" => "no_candidate"})
  end

  defp issue_codes(%FinalError{} = error), do: Enum.map(error.issues, & &1["code"])

  defp issue_codes(%NonRecError{} = exception) do
    persisted = exception |> ErrorParser.parse() |> Jason.encode!() |> Jason.decode!()

    case TaskFailure.decode(persisted) do
      {:ok, error} -> issue_codes(error)
      :error -> raise "the failure does not decode as a typed Final failure"
    end
  end
end
