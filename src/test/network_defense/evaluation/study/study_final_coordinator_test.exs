defmodule NetworkDefense.Evaluation.Study.FinalCoordinatorTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{Coordinator, PilotOutcome, Results}

  alias NetworkDefense.Evaluation.{
    FinalConformance,
    PilotConformance,
    StudyExecution,
    StudyFixtures,
    StudyPhase,
    StudyResult
  }

  defmodule Store do
    use Agent

    def start_link(value), do: Agent.start_link(fn -> value end, name: __MODULE__)
    def get(key), do: Agent.get(__MODULE__, &Map.fetch!(&1, key))
    def put(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  defmodule FinalCollectionWorkflowStub do
    def create(phase) do
      send(Store.get(:owner), {:final_collection_created, phase.id})
      {:ok, 902}
    end

    def dispatch(902) do
      send(Store.get(:owner), :final_collection_dispatched)
      :ok
    end

    def await(902) do
      if Store.get(:block_collection) do
        send(Store.get(:owner), {:final_collection_waiting, self()})
        receive do: (:continue_final_collection -> :ok)
      end

      Store.get(:collection_result)
    end
  end

  defmodule FinalWorkflowStub do
    def create(params) do
      with {:ok, %Request{} = request} <- Request.parse(params) do
        Store.put(:final_result, FinalConformance.result!(request, Store.get(:fixture)))
        send(Store.get(:owner), {:final_analysis_created, request})
        {:ok, 903}
      end
    end

    def dispatch(903) do
      send(Store.get(:owner), :final_analysis_dispatched)
      :ok
    end

    def await(903) do
      if Store.get(:block_analysis) do
        send(Store.get(:owner), {:final_analysis_waiting, self()})
        receive do: (:continue_final_analysis -> :ok)
      end

      Store.get(:analysis_result)
    end

    def result(903), do: {:ok, Store.get(:final_result)}
  end

  setup do
    fixture = StudyFixtures.final_conformance_fixture()
    context = StudyFixtures.persist_final_conformance_lifecycle!(901)

    {:ok, pilot_snapshot} =
      PilotConformance.store_snapshot(PilotConformance.snapshot())

    {:ok, final_snapshot} =
      FinalConformance.store_snapshot(fixture.snapshot)

    pilot_collection = StudyFixtures.insert_phase(context.execution, :pilot_collection)

    pilot_collection
    |> StudyPhase.changeset(%{gust_run_id: 801, snapshot_id: pilot_snapshot.id})
    |> Repo.update!()

    start_supervised!(
      {Store,
       %{
         owner: self(),
         block_collection: false,
         block_analysis: false,
         collection_result: {:ok, final_snapshot.id},
         analysis_result: {:ok, :succeeded},
         final_result: nil,
         fixture: fixture
       }}
    )

    Map.merge(context, %{final_snapshot: final_snapshot})
  end

  test "F21-01: WHEN Final analysis returns one valid complete family, THE coordinator SHALL store one compact result and succeed",
       context do
    assert :ok = run(context.execution.id)

    assert_receive {:final_collection_created, phase_id}
    assert phase_id == context.final_phase.id
    assert_receive :final_collection_dispatched
    assert_receive {:final_analysis_created, request}
    assert request.study_execution_id == context.execution.id
    assert request.source_pilot_run_id == context.pilot_phase.gust_run_id
    assert_receive :final_analysis_dispatched

    execution = Repo.get!(StudyExecution, context.execution.id)
    assert execution.state == :succeeded
    assert Repo.aggregate(StudyResult, :count, :id) == 1
    assert {:ok, compact} = Results.get_for_execution(execution.id)
    assert compact.final_result.family_size == 2
  end

  test "F20-02: WHEN an insufficient Pilot has an approved frozen override, THE coordinator SHALL complete Final analysis and preserve insufficiency",
       context do
    outcome = %PilotOutcome{outcome: :insufficient, reason: "no_passing_candidate"}
    outcome_params = PilotOutcome.to_params(outcome)

    context.execution
    |> StudyExecution.changeset(%{pilot_outcome: outcome_params, pilot_override: true})
    |> Repo.update!()

    context.pilot_phase
    |> StudyPhase.changeset(%{result_ref: outcome_params})
    |> Repo.update!()

    assert :ok = run(context.execution.id)
    assert Repo.get!(StudyExecution, context.execution.id).state == :succeeded
    assert {:ok, compact} = Results.get_for_execution(context.execution.id)
    assert compact.selection.pilot_override == true
    assert compact.pilot_analysis.outcome.outcome == :insufficient
  end

  test "F21-02: WHEN cancellation commits before late Final completion, THE coordinator SHALL keep cancelled and store no compact result",
       context do
    Store.put(:block_analysis, true)

    task = Task.async(fn -> run(context.execution.id) end)
    assert_receive {:final_analysis_waiting, coordinator_pid}, 2_000

    context.execution
    |> Repo.reload!()
    |> StudyExecution.changeset(%{state: :cancelled})
    |> Repo.update!()

    send(coordinator_pid, :continue_final_analysis)
    assert Task.await(task, 2_000) == :ok

    assert Repo.get!(StudyExecution, context.execution.id).state == :cancelled
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "F21-03: WHEN Final collection fails terminally, THE coordinator SHALL store one bounded error without a result",
       context do
    Store.put(:collection_result, {:error, StudyError.final_collection_workflow_failed()})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    phase = Repo.get!(StudyPhase, context.final_phase.id)
    assert execution.state == :failed
    assert execution.error == phase.error
    assert Jason.encode!(execution.error) =~ "final_collection_workflow_failed"
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  test "F21-03: WHEN Final analysis fails terminally, THE coordinator SHALL store one bounded error without a result",
       context do
    Store.put(:analysis_result, {:error, FinalError.workflow_failed()})

    assert {:error, %StudyError{}} = run(context.execution.id)

    execution = Repo.get!(StudyExecution, context.execution.id)
    phase = Repo.get_by!(StudyPhase, execution_id: execution.id, phase: :final_analysis)
    assert execution.state == :failed
    assert execution.error == phase.error
    assert Jason.encode!(execution.error) =~ "final_analysis_failed"
    assert Repo.aggregate(StudyResult, :count, :id) == 0
  end

  defp run(execution_id) do
    Coordinator.run(execution_id,
      final_collection_workflow: FinalCollectionWorkflowStub,
      final_workflow: FinalWorkflowStub
    )
  end
end
