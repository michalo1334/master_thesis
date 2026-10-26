defmodule NetworkDefense.Evaluation.Final.LimitsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.Flows

  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Final

  alias NetworkDefense.Evaluation.Final.Actions.{
    CompareFinalMember,
    CorrectFinalFamily,
    PrepareFinal
  }

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}
  alias NetworkDefense.Evaluation.Final.{Limits, Member, TaskFailure}
  alias NetworkDefense.Evaluation.FinalComputeStub
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.StudyFixtures

  # Acceptance coverage in this file:
  #   S5-03  a source that cannot be computed stays rejected before any run
  #   S5-04  copied counts and settings are checked before submission
  #
  # Review finding P1 (unbounded bootstrap work): the comparison endpoint has no
  # resource cap from the Pilot configuration. Final therefore enforces its own
  # configured replicate and total-work caps before Gust submission and again on
  # every persisted request that reaches a Final task.

  @config NetworkDefense.Evaluation.Final.Limits
  @max_replicates 1_000
  @max_work 1_000_000

  setup do
    gust_owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    owner = Sandbox.start_owner!(NetworkDefense.Repo, shared: true)

    on_exit(fn ->
      Sandbox.stop_owner(owner)
      Sandbox.stop_owner(gust_owner)
    end)

    :ok = FinalComputeStub.start_gust!()
    fixture = final_fixture()
    agent = FinalComputeStub.start!(final_fixture: fixture)
    pilot_run_id = FinalComputeStub.recommended_pilot_run!()
    lifecycle = StudyFixtures.persist_final_conformance_lifecycle!(pilot_run_id)

    assert {:ok, snapshot} =
             FinalConformance.store_snapshot(fixture.snapshot)

    _accepted = StudyFixtures.accept_final_collection!(lifecycle, snapshot.id)

    %{
      agent: agent,
      pilot_run_id: pilot_run_id,
      snapshot: snapshot,
      final_runs_before: runs_on_final_dag()
    }
  end

  describe "work units" do
    test "LIMITS-01: one work unit is one resample of one declared comparison", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      request = parsed_request!(snapshot.id, pilot_run_id)

      # Two declared comparisons, two plan sides of six rows, ten shared attack
      # columns, and five hundred replicates.
      assert Limits.work_units(request) == 2 * (2 * 6 * 10) * 500
      assert Limits.work_units(request) == 120_000
    end

    test "LIMITS-02: the guard rejects one replicate or one work unit above the cap", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      request = parsed_request!(snapshot.id, pilot_run_id)

      assert :ok = Limits.validate(at_replicates(request, @max_replicates))

      assert {:error, %FinalError{code: "validation_failed", issues: [issue]}} =
               Limits.validate(at_replicates(request, @max_replicates + 1))

      assert issue["code"] == "bootstrap_replicates_exceeded"
      assert issue["path"] == ["analysis", "bootstrap_replicates"]

      # Replicates stay at the cap while the aggregate work crosses it. Two
      # declared comparisons times two plan sides of six rows times forty-one
      # columns times one thousand replicates stays below one million; forty-two
      # columns crosses it.
      assert Limits.work_units(at_columns(request, 41)) == 984_000
      assert :ok = Limits.validate(at_columns(request, 41))

      assert {:error, %FinalError{issues: [work_issue]}} =
               Limits.validate(at_columns(request, 42))

      assert work_issue["code"] == "work_limit_exceeded"
    end

    test "LIMITS-03: a one-billion-replicate request is rejected without a run", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      final_runs_before: final_runs_before
    } do
      params =
        request_params!(snapshot.id, pilot_run_id)
        |> Map.put("analysis", %{
          "alpha" => 0.05,
          "confidence_level" => 0.95,
          "test_alternative" => "two_sided",
          "bootstrap_replicates" => 1_000_000_000_000
        })

      assert {:error, %FinalError{code: "validation_failed", issues: [issue]}} =
               FinalConformance.submit(params)

      assert issue["code"] == "bootstrap_replicates_exceeded"
      assert runs_on_final_dag() == final_runs_before
    end
  end

  describe "configuration" do
    setup do
      on_exit(fn ->
        Application.put_env(:network_defense, @config,
          max_bootstrap_replicates: @max_replicates,
          max_total_work: @max_work
        )
      end)
    end

    test "LIMITS-04: a missing configuration rejects Final and starts no run", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      final_runs_before: final_runs_before
    } do
      Application.delete_env(:network_defense, @config)

      params = request_params!(snapshot.id, pilot_run_id)

      assert {:error, %FinalError{code: "workflow_failed", issues: [issue]}} =
               FinalConformance.submit(params)

      assert issue["code"] == "configuration_invalid"
      assert runs_on_final_dag() == final_runs_before
    end

    test "LIMITS-05: a partial or malformed configuration rejects Final", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      final_runs_before: final_runs_before
    } do
      params = request_params!(snapshot.id, pilot_run_id)

      malformed = [
        [max_bootstrap_replicates: @max_replicates],
        [max_total_work: @max_work],
        [max_bootstrap_replicates: 0, max_total_work: @max_work],
        [max_bootstrap_replicates: @max_replicates, max_total_work: -1],
        [max_bootstrap_replicates: 1.0, max_total_work: @max_work],
        %{max_bootstrap_replicates: "1000", max_total_work: @max_work},
        :unset,
        "caps",
        # An unknown key is a deployment mistake, not a missing value.
        [
          max_bootstrap_replicates: @max_replicates,
          max_total_work: @max_work,
          max_member_requests: 1
        ],
        %{
          max_bootstrap_replicates: @max_replicates,
          max_total_work: @max_work,
          extra: 1
        },
        # A list must be a keyword list with exactly the two required keys.
        [{:max_bootstrap_replicates, @max_replicates}, {:max_total_work, @max_work} | :tail],
        [:junk, max_bootstrap_replicates: @max_replicates, max_total_work: @max_work],
        [{:max_bootstrap_replicates, @max_replicates, :extra}, {:max_total_work, @max_work}],
        %{"max_bootstrap_replicates" => @max_replicates, "max_total_work" => @max_work},
        %{},
        []
      ]

      for config <- malformed do
        Application.put_env(:network_defense, @config, config)

        assert {:error, %FinalError{code: "workflow_failed", issues: [issue]}} =
                 FinalConformance.submit(params),
               "expected a bounded configuration error for #{inspect(config)}"

        assert issue["code"] == "configuration_invalid"
      end

      assert runs_on_final_dag() == final_runs_before
    end

    test "LIMITS-11: a keyword list and an atom-key map are both accepted", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      params = request_params!(snapshot.id, pilot_run_id)

      for config <- [
            [max_bootstrap_replicates: @max_replicates, max_total_work: @max_work],
            %{max_bootstrap_replicates: @max_replicates, max_total_work: @max_work}
          ] do
        Application.put_env(:network_defense, @config, config)

        assert {:ok, limits} = Limits.fetch()
        assert limits == %{max_bootstrap_replicates: @max_replicates, max_total_work: @max_work}

        assert {:ok, _run_id} = FinalConformance.submit(params)
      end
    end

    test "LIMITS-12: a repeated keyword key keeps its first value", %{} do
      Application.put_env(:network_defense, @config,
        max_bootstrap_replicates: 5,
        max_total_work: @max_work,
        max_bootstrap_replicates: @max_replicates
      )

      assert {:ok, limits} = Limits.fetch()
      assert limits.max_bootstrap_replicates == 5
    end

    test "LIMITS-06: the guard never borrows the Pilot caps", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      final_runs_before: final_runs_before
    } do
      # The synthetic Pilot caps allow 1_024 replicates. Final still refuses
      # more than its own configured ceiling.
      assert Application.fetch_env!(:network_defense, NetworkDefense.Evaluation.Pilot.Limits)[
               :bootstrap_replicates
             ] == 1_024

      params =
        request_params!(snapshot.id, pilot_run_id)
        |> Map.put("analysis", %{
          "alpha" => 0.05,
          "confidence_level" => 0.95,
          "test_alternative" => "two_sided",
          "bootstrap_replicates" => 1_024
        })

      assert {:error, %FinalError{issues: [issue]}} = FinalConformance.submit(params)
      assert issue["code"] == "bootstrap_replicates_exceeded"
      assert runs_on_final_dag() == final_runs_before
    end
  end

  describe "persisted requests" do
    test "LIMITS-07: a persisted over-cap request stops preparation before any item", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = over_cap_run!(snapshot.id, pilot_run_id)

      exception = assert_raise(NonRecError, fn -> PrepareFinal.execute([], %{run_id: run.id}) end)

      assert "bootstrap_replicates_exceeded" in issue_codes(exception)
    end

    test "LIMITS-08: a persisted over-cap request stops a member before its compute call", %{
      agent: agent,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = over_cap_run!(snapshot.id, pilot_run_id)
      item = declared_item!(snapshot.id, pilot_run_id, 0)

      exception =
        assert_raise(NonRecError, fn ->
          CompareFinalMember.execute([item: item], %{run_id: run.id})
        end)

      assert "bootstrap_replicates_exceeded" in issue_codes(exception)
      assert FinalComputeStub.requests(agent, :comparison_seeds) == []
    end

    test "LIMITS-09: a persisted over-cap request stops the fan-in before the correction", %{
      agent: agent,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = over_cap_run!(snapshot.id, pilot_run_id)

      exception =
        assert_raise(NonRecError, fn ->
          CorrectFinalFamily.execute([], %{run_id: run.id})
        end)

      assert "bootstrap_replicates_exceeded" in issue_codes(exception)
      assert FinalComputeStub.requests(agent, :correction_requests) == []
    end

    test "LIMITS-10: a persisted request at the cap still prepares", %{
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run_at_cap!(snapshot.id, pilot_run_id)

      assert %{"gust_task_items" => items} = PrepareFinal.execute([], %{run_id: run.id})

      assert Enum.map(items, & &1["position"]) == [0, 1]
    end
  end

  describe "shared snapshot configuration" do
    setup do
      shared = NetworkDefense.Evaluation.Pilot.Limits
      original = Application.fetch_env!(:network_defense, shared)

      on_exit(fn -> Application.put_env(:network_defense, shared, original) end)

      %{shared: shared, original: original}
    end

    test "LIMITS-13: a missing shared snapshot configuration stays a Final error", %{
      shared: shared,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      final_runs_before: final_runs_before
    } do
      Application.delete_env(:network_defense, shared)
      rows_before = final_snapshot_rows()

      assert {:error, %FinalError{code: "workflow_failed", issues: [issue]}} =
               FinalConformance.store_snapshot(FinalConformance.snapshot())

      assert issue["code"] == "configuration_invalid"
      assert final_snapshot_rows() == rows_before

      assert {:error, %FinalError{issues: [read_issue]}} =
               EvidenceSnapshots.get_final(snapshot.id)

      assert read_issue["code"] == "configuration_invalid"

      assert {:error, %FinalError{issues: [submit_issue]}} =
               FinalConformance.submit(request_params!(snapshot.id, pilot_run_id))

      assert submit_issue["code"] == "configuration_invalid"
      assert runs_on_final_dag() == final_runs_before
    end

    test "LIMITS-14: a malformed shared snapshot configuration stays a Final error", %{
      shared: shared,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id,
      final_runs_before: final_runs_before
    } do
      Application.put_env(
        :network_defense,
        shared,
        Keyword.drop(Application.fetch_env!(:network_defense, shared), [:attack_columns])
      )

      assert {:error, %FinalError{issues: [create_issue]}} =
               FinalConformance.store_snapshot(FinalConformance.snapshot())

      assert create_issue["code"] == "configuration_invalid"

      assert {:error, %FinalError{issues: [submit_issue]}} =
               FinalConformance.submit(request_params!(snapshot.id, pilot_run_id))

      assert submit_issue["code"] == "configuration_invalid"
      assert runs_on_final_dag() == final_runs_before
    end

    test "LIMITS-15: every persisted boundary reports the shared configuration as Final", %{
      shared: shared,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      run = run_at_cap!(snapshot.id, pilot_run_id)
      item = declared_item!(snapshot.id, pilot_run_id, 0)

      assert %{"gust_task_items" => _items} = PrepareFinal.execute([], %{run_id: run.id})

      Application.delete_env(:network_defense, shared)

      prepare_failure =
        assert_raise(NonRecError, fn -> PrepareFinal.execute([], %{run_id: run.id}) end)

      assert "configuration_invalid" in issue_codes(prepare_failure)

      member_failure =
        assert_raise(NonRecError, fn ->
          CompareFinalMember.execute([item: item], %{run_id: run.id})
        end)

      assert "configuration_invalid" in issue_codes(member_failure)

      fan_in_failure =
        assert_raise(NonRecError, fn -> CorrectFinalFamily.execute([], %{run_id: run.id}) end)

      assert "configuration_invalid" in issue_codes(fan_in_failure)
    end

    test "LIMITS-16: a successful result read reports the shared configuration as Final", %{
      shared: shared,
      snapshot: snapshot,
      pilot_run_id: pilot_run_id
    } do
      assert {:ok, run_id} =
               FinalConformance.submit(request_params!(snapshot.id, pilot_run_id))

      assert {:ok, :succeeded} = Final.Workflow.await(run_id, 20_000)

      Application.delete_env(:network_defense, shared)

      assert {:error, %FinalError{issues: [issue]}} = Final.Workflow.result(run_id)
      assert issue["code"] == "configuration_invalid"
    end
  end

  defp request_params!(snapshot_id, pilot_run_id) do
    FinalConformance.request_params!(
      snapshot_id,
      pilot_run_id,
      accepted_execution_id!(snapshot_id),
      final_fixture()
    )
  end

  defp parsed_request!(snapshot_id, pilot_run_id) do
    FinalConformance.parsed_request!(
      snapshot_id,
      pilot_run_id,
      accepted_execution_id!(snapshot_id),
      final_fixture()
    )
  end

  defp accepted_execution_id!(snapshot_id) do
    phase =
      NetworkDefense.Repo.get_by!(NetworkDefense.Evaluation.StudyPhase,
        snapshot_id: snapshot_id
      )

    phase.execution_id
  end

  defp final_fixture, do: StudyFixtures.final_conformance_fixture()

  defp at_replicates(%Request{} = request, replicates) do
    %{request | analysis: %{request.analysis | bootstrap_replicates: replicates}}
  end

  defp at_columns(%Request{} = request, columns) do
    %{at_replicates(request, @max_replicates) | attacks_per_plan: columns}
  end

  defp over_cap_run!(snapshot_id, pilot_run_id) do
    params =
      request_params!(snapshot_id, pilot_run_id)
      |> Map.put("analysis", %{
        "alpha" => 0.05,
        "confidence_level" => 0.95,
        "test_alternative" => "two_sided",
        "bootstrap_replicates" => @max_replicates + 1
      })

    {:ok, dag} = Flows.create_dag(%{name: unique_dag_name()})
    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: params})
    run
  end

  defp run_at_cap!(snapshot_id, pilot_run_id) do
    params =
      request_params!(snapshot_id, pilot_run_id)
      |> Map.put("analysis", %{
        "alpha" => 0.05,
        "confidence_level" => 0.95,
        "test_alternative" => "two_sided",
        "bootstrap_replicates" => @max_replicates
      })

    {:ok, dag} = Flows.create_dag(%{name: unique_dag_name()})
    {:ok, run} = Flows.create_run(%{dag_id: dag.id, params: params})
    run
  end

  defp declared_item!(snapshot_id, pilot_run_id, position) do
    request = parsed_request!(snapshot_id, pilot_run_id)
    Enum.at(Member.declared_items(request), position)
  end

  defp issue_codes(exception) do
    persisted = exception |> ErrorParser.parse() |> Jason.encode!() |> Jason.decode!()

    case TaskFailure.decode(persisted) do
      {:ok, error} -> Enum.map(error.issues, & &1["code"])
      :error -> raise "the failure does not decode as a typed Final failure"
    end
  end

  defp unique_dag_name do
    "evaluation_final_limits_#{System.unique_integer([:positive])}"
  end

  defp runs_on_final_dag do
    case Flows.get_dag_by_name("evaluation_final") do
      nil -> 0
      dag -> Flows.count_runs_on_dag(dag.id)
    end
  end

  defp final_snapshot_rows do
    NetworkDefense.Repo.aggregate(
      from(snapshot in NetworkDefense.Evaluation.EvidenceSnapshot,
        where: snapshot.phase == :final
      ),
      :count
    )
  end
end
