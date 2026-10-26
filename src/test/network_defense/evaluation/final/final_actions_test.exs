defmodule NetworkDefense.Evaluation.Final.ActionsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.Flows

  alias NetworkDefense.Evaluation.Family.Contracts.Identity
  alias NetworkDefense.Evaluation.Final.Actions.{CorrectFinalFamily, PrepareFinal}
  alias NetworkDefense.Evaluation.Final.Collector
  alias NetworkDefense.Evaluation.Final.Contracts.Request
  alias NetworkDefense.Evaluation.Final.Member
  alias NetworkDefense.Evaluation.Final.TaskFailure
  alias NetworkDefense.Evaluation.Final.TaskFailure.RetryableError
  alias NetworkDefense.Evaluation.FinalComputeStub
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.StudyFixtures
  alias NetworkDefense.Repo

  # Acceptance coverage in this file:
  #   S5-06  one invalid member fails the family; no accepted member result
  #   S5-07  missing, duplicate, unexpected, failed, or reordered members reject
  #          the family, with no partial correction

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    owner = Sandbox.start_owner!(Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(owner)
      Sandbox.stop_owner(gust_owner)
    end)

    :ok = FinalComputeStub.start_gust!()
    fixture = final_fixture()
    agent = FinalComputeStub.start!(final_fixture: fixture)
    pilot_run_id = FinalComputeStub.recommended_pilot_run!()
    lifecycle = StudyFixtures.persist_final_conformance_lifecycle!(pilot_run_id)

    {:ok, dag} =
      Flows.create_dag(%{name: "evaluation_final_actions_#{System.unique_integer([:positive])}"})

    assert {:ok, snapshot} =
             FinalConformance.store_snapshot(fixture.snapshot)

    _accepted = StudyFixtures.accept_final_collection!(lifecycle, snapshot.id)

    %{dag: dag, snapshot: snapshot, pilot_run_id: pilot_run_id, agent: agent}
  end

  describe "collector" do
    test "COLLECT-01: members are collected by declared position, not completion order", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      persist_tasks!(run, Enum.reverse(members!(run, snapshot.id)))

      assert {:ok, collected} = collect(run, snapshot.id)
      assert Enum.map(collected, &Identity.key(&1.identity)) == declared_keys()
    end

    test "COLLECT-02: a missing member rejects the family", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      [first, _second] = members!(run, snapshot.id)
      persist_tasks!(run, [first])

      assert {:error, error} = collect(run, snapshot.id)
      assert "incomplete_family" in issue_codes(error)
    end

    test "COLLECT-03: an unexpected extra member rejects the family", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      [first | _rest] = members = members!(run, snapshot.id)
      persist_tasks!(run, members ++ [%{first | map_index: 2}])

      assert {:error, error} = collect(run, snapshot.id)
      assert "incomplete_family" in issue_codes(error)
    end

    test "COLLECT-04: a member that did not succeed rejects the family", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      [first, second] = members!(run, snapshot.id)
      persist_tasks!(run, [first, %{second | status: :failed}])

      assert {:error, error} = collect(run, snapshot.id)
      assert "incomplete_family" in issue_codes(error)
    end

    test "COLLECT-05: indices that are not zero-based reject the family", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      [first, second] = members!(run, snapshot.id)
      persist_tasks!(run, [%{first | map_index: 1}, %{second | map_index: 5}])

      assert {:error, error} = collect(run, snapshot.id)
      assert "incomplete_family" in issue_codes(error)
    end

    test "COLLECT-06: a member stored under the wrong position rejects the family", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      [first, second] = members!(run, snapshot.id)

      swapped = [
        %{
          first
          | params: second.params,
            result: %{first.result | "identity" => second.params["identity"]}
        },
        %{
          second
          | params: first.params,
            result: %{second.result | "identity" => first.params["identity"]}
        }
      ]

      persist_tasks!(run, swapped)

      assert {:error, error} = collect(run, snapshot.id)
      assert "changed_family_member" in issue_codes(error)
    end

    test "COLLECT-07: member statistics that do not fit their request reject the family", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      [first, second] = members!(run, snapshot.id)

      broken = first.result["statistics"] |> Map.delete("interval")

      persist_tasks!(run, [
        %{first | result: %{first.result | "statistics" => broken}},
        second
      ])

      assert {:error, error} = collect(run, snapshot.id)
      assert "incomplete_family" in issue_codes(error)
    end

    test "COLLECT-08: persisted preparation that differs from the declared family rejects", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run!(dag, snapshot.id, pilot_run_id)

      {:ok, _task} =
        Flows.create_task(%{
          run_id: run.id,
          name: "prepare_final",
          status: :succeeded,
          result: %{"gust_task_items" => [%{"position" => 0, "identity" => %{}}]}
        })

      assert {:error, error} = collect(run, snapshot.id)
      assert "incomplete_family" in issue_codes(error)
    end
  end

  describe "correction" do
    test "ACTIONS-01: one correction call covers the complete declared family", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      agent: agent
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      persist_tasks!(run, Enum.reverse(members!(run, snapshot.id)))

      assert %{"schema_version" => 1, "comparisons" => comparisons} =
               CorrectFinalFamily.execute([], %{run_id: run.id})

      assert Enum.map(comparisons, & &1["identity"]) == declared_identities()

      assert Enum.map(comparisons, & &1["statistics"]["test"]["raw_p_value"]) ==
               FinalConformance.raw_p_values()

      assert Enum.map(comparisons, & &1["adjustment"]["adjusted_p_value"]) ==
               Enum.map(
                 final_fixture().correction_response["results"],
                 & &1["adjusted_p_value"]
               )

      assert [correction] = FinalComputeStub.requests(agent, :correction_requests)
      assert correction["family_id"] == "family-example"
      assert correction["alpha"] == 0.05

      assert Enum.map(correction["raw_results"], & &1["raw_p_value"]) ==
               FinalConformance.raw_p_values()
    end

    test "ACTIONS-02: an incomplete family makes no correction call", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      agent: agent
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      [first, _second] = members!(run, snapshot.id)
      persist_tasks!(run, [first])

      exception =
        assert_raise(NonRecError, fn -> CorrectFinalFamily.execute([], %{run_id: run.id}) end)

      assert "incomplete_family" in failure_issue_codes(exception)
      assert FinalComputeStub.requests(agent, :correction_requests) == []
    end

    test "ACTIONS-03: an unreachable correction service stays retryable", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      FinalComputeStub.configure_clients!(1)
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      persist_tasks!(run, members!(run, snapshot.id))

      exception =
        assert_raise(RetryableError, fn ->
          CorrectFinalFamily.execute([], %{run_id: run.id})
        end)

      # A short outage must not end the family. The classification comes from
      # the correction client, so Gust can retry only this pure call.
      assert "compute_unavailable" in failure_issue_codes(exception)
    end

    test "ACTIONS-06: a documented 503 correction reply stays retryable", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      agent: agent
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      persist_tasks!(run, members!(run, snapshot.id))

      FinalComputeStub.fail_correction!(agent, 503, "compute_unavailable")

      exception =
        assert_raise(RetryableError, fn ->
          CorrectFinalFamily.execute([], %{run_id: run.id})
        end)

      assert failure_issue_codes(exception) == ["compute_unavailable"]
    end

    test "ACTIONS-07: a valid permanent correction diagnostic keeps its rows", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      agent: agent
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      persist_tasks!(run, members!(run, snapshot.id))

      FinalComputeStub.fail_correction!(agent, 400, "validation_failed")

      exception =
        assert_raise(NonRecError, fn -> CorrectFinalFamily.execute([], %{run_id: run.id}) end)

      # The service rejected the correction for a contract reason. The owning
      # error keeps that code instead of reporting a malformed response.
      assert failure_codes(exception) == ["validation_failed"]
      assert failure_issue_codes(exception) == ["invalid_type"]
    end

    test "ACTIONS-08: a valid schema-diagnostic correction reply keeps its diagnostics", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      agent: agent
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      persist_tasks!(run, members!(run, snapshot.id))

      diagnostics = %{
        "schema_version" => 1,
        "error" => %{
          "code" => "validation_failed",
          "schema_errors" => [
            %{"message" => "The correction request is not valid.", "path" => "#", "causes" => []}
          ]
        }
      }

      FinalComputeStub.fail_correction!(agent, 422, diagnostics)

      exception =
        assert_raise(NonRecError, fn -> CorrectFinalFamily.execute([], %{run_id: run.id}) end)

      assert failure_codes(exception) == ["validation_failed"]

      assert failure_diagnostics(exception) == ["The correction request is not valid."],
             "schema diagnostics must survive the conversion"
    end

    test "ACTIONS-09: a malformed correction reply stays permanently invalid", %{
      dag: dag,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      agent: agent
    } do
      run = run!(dag, snapshot.id, pilot_run_id)
      prepared!(run, snapshot.id)
      persist_tasks!(run, members!(run, snapshot.id))

      FinalComputeStub.fail_correction!(agent, 400, %{"unexpected" => true})

      exception =
        assert_raise(NonRecError, fn -> CorrectFinalFamily.execute([], %{run_id: run.id}) end)

      assert failure_codes(exception) == ["invalid_response_contract"]
      assert failure_issue_codes(exception) == ["invalid_response_contract"]
    end
  end

  describe "preparation" do
    test "ACTIONS-04: preparation rejects a Pilot run that is not the accepted lifecycle source",
         %{
           dag: dag,
           snapshot: snapshot
         } do
      run = run!(dag, snapshot.id, 987_654_321)

      exception =
        assert_raise(NonRecError, fn -> PrepareFinal.execute([], %{run_id: run.id}) end)

      assert "changed_pilot_source" in failure_issue_codes(exception)
    end
  end

  defp run!(dag, snapshot_id, source_pilot_run_id, overrides \\ []) do
    params =
      FinalConformance.request_params!(
        snapshot_id,
        source_pilot_run_id,
        accepted_execution_id!(snapshot_id),
        final_fixture()
      )
      |> Map.merge(Map.new(overrides, fn {key, value} -> {Atom.to_string(key), value} end))

    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: params})
    run
  end

  defp prepared!(run, _snapshot_id) do
    {:ok, request} = Request.parse(run.params)

    {:ok, _task} =
      Flows.create_task(%{
        run_id: run.id,
        name: "prepare_final",
        status: :succeeded,
        result: %{"gust_task_items" => Member.declared_items(request)}
      })
  end

  defp members!(_run, _snapshot_id) do
    final_fixture().member_requests
    |> Enum.with_index()
    |> Enum.map(fn {request, position} ->
      identity = Enum.at(declared_identities(), position)

      %{
        map_index: position,
        params: %{"position" => position, "identity" => identity},
        status: :succeeded,
        result: %{
          "identity" => identity,
          "statistics" => FinalConformance.response_for(request, final_fixture())
        }
      }
    end)
  end

  defp persist_tasks!(run, members) do
    Enum.each(members, fn member ->
      {:ok, _task} =
        Flows.create_task(%{
          run_id: run.id,
          name: "compare_final_member",
          map_index: member.map_index,
          status: member.status,
          params: member.params,
          result: member.result
        })
    end)
  end

  defp collect(run, _snapshot_id) do
    {:ok, request} = Request.parse(run.params)
    Collector.collect(run.id, request, FinalConformance.parsed_payload!(final_fixture()))
  end

  defp accepted_execution_id!(snapshot_id) do
    phase = Repo.get_by!(NetworkDefense.Evaluation.StudyPhase, snapshot_id: snapshot_id)
    phase.execution_id
  end

  defp final_fixture, do: StudyFixtures.final_conformance_fixture()

  defp declared_identities do
    final_fixture().snapshot["payload"]["comparisons"]
    |> Enum.map(&Map.fetch!(&1, "identity"))
  end

  defp declared_keys do
    final_fixture().snapshot["payload"]["comparisons"]
    |> Enum.map(fn comparison ->
      identity = comparison["identity"]

      {identity["tier"], identity["budget"], identity["alternative"], identity["reference"],
       identity["outcome"]}
    end)
  end

  defp failure_issue_codes(exception) do
    case decode_failure(exception) do
      {:ok, error} -> issue_codes(error)
      :error -> raise "the failure does not decode as a typed Final failure"
    end
  end

  defp failure_codes(exception) do
    case decode_failure(exception) do
      {:ok, error} -> [error.code]
      :error -> raise "the failure does not decode as a typed Final failure"
    end
  end

  defp failure_diagnostics(exception) do
    case decode_failure(exception) do
      {:ok, error} -> Enum.map(error.schema_errors, & &1["message"])
      :error -> raise "the failure does not decode as a typed Final failure"
    end
  end

  defp decode_failure(exception) do
    exception |> ErrorParser.parse() |> Jason.encode!() |> Jason.decode!() |> TaskFailure.decode()
  end

  defp issue_codes(%{issues: issues}), do: Enum.map(issues, & &1["code"])
end
