defmodule NetworkDefense.Evaluation.Study.PublicJourneyTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation.EvidenceSnapshots
  alias NetworkDefense.Evaluation.Final.Contracts.Request, as: FinalRequest
  alias NetworkDefense.Evaluation.Final.Workflow, as: FinalWorkflow
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotResult, Recommendation}
  alias NetworkDefense.Evaluation.Pilot.Workflow, as: PilotWorkflow
  alias NetworkDefense.Evaluation.Study.{CollectionWorkflow, FinalCollectionWorkflow}
  alias NetworkDefense.Evaluation.Study.{CompactResult, PilotOutcome, PilotSnapshot}
  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.{StudyExecution, StudyFixtures, StudyResult}
  alias NetworkDefense.Evaluations

  # The two required public journeys:
  #
  #   STUDY-JOURNEY-01  a recommended Pilot pauses, resumes with `:recommended`,
  #                     completes Final analysis, and returns one compact result
  #                     with `pilot_override: false`
  #   STUDY-JOURNEY-02  an insufficient Pilot rejects `:recommended`, accepts the
  #                     declared override, completes Final analysis, and returns
  #                     one compact result with `pilot_override: true`
  #
  # Both call only the public functions: `start_study/1`, `study_status/1`,
  # `resume_study/2`, and `study_result/1`. The real coordinator runs the
  # lifecycle, including its own fixed phase rows.
  #
  # The four fixed workflows are replaced at their Gust transport boundary with
  # `meck`, which is the seam the existing rescue suite uses. Run creation,
  # dispatch, waiting, and result storage are stand-ins. The coordinator, the
  # request builders, the snapshot checks, and the result validation are real.
  # The collection stand-in runs the real collection items, so the accepted
  # Pilot snapshot is real evidence.

  @workflow_modules [
    CollectionWorkflow,
    PilotWorkflow,
    FinalCollectionWorkflow,
    FinalWorkflow
  ]

  @coordinator_timeout 30_000

  defmodule Store do
    use Agent

    def start_link(value), do: Agent.start_link(fn -> value end, name: __MODULE__)
    def get(key), do: Agent.get(__MODULE__, &Map.fetch!(&1, key))
    def put(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  setup do
    core = StudyFixtures.insert_collection_graph("study-journey-core", mission: true)
    edge = StudyFixtures.insert_collection_graph("study-journey-edge", mission: true)
    definition = StudyFixtures.conformance_journey_definition!(core, edge)
    final_fixture = StudyFixtures.final_conformance_fixture()

    revision =
      StudyFixtures.insert_revision(%{
        id: FinalConformance.request()["study_revision_id"],
        definition: Definition.to_params(definition)
      })

    {:ok, final_snapshot} =
      EvidenceSnapshots.create_final(FinalConformance.snapshot_input!(final_fixture))

    candidate = Enum.find(definition.pilot.candidates, &(&1.id == "medium"))

    start_supervised!(
      {Store,
       %{
         definition: definition,
         final_fixture: final_fixture,
         final_snapshot_id: final_snapshot.id,
         final_result: nil,
         pilot_snapshot_id: nil,
         pilot_result: {:ok, recommended(candidate)}
       }}
    )

    install_workflow_boundaries!()

    %{
      revision: revision,
      definition: definition,
      candidate: candidate,
      final_snapshot: final_snapshot
    }
  end

  test "STUDY-JOURNEY-01: WHEN a valid study produces a recommended Pilot, THE public API SHALL pause, resume with :recommended, complete Final analysis, and return one compact result with pilot_override false",
       context do
    assert {:ok, %StudyExecution{state: :collecting_pilot} = started} =
             Evaluations.start_study(context.revision.id)

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :awaiting_final} = paused} =
             Evaluations.study_status(started.id)

    assert {:ok, %PilotOutcome{outcome: :recommended, candidate_id: candidate_id}} =
             PilotOutcome.parse(paused.pilot_outcome)

    assert candidate_id == context.candidate.id

    assert {:ok, %StudyExecution{state: :collecting_final}} =
             Evaluations.resume_study(started.id, :recommended)

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :succeeded}} = Evaluations.study_status(started.id)

    assert {:ok, %CompactResult{} = compact} = Evaluations.study_result(started.id)

    assert compact.execution_id == started.id
    assert compact.study_revision_id == context.revision.id
    assert compact.selection.candidate_id == context.candidate.id
    assert compact.selection.pilot_override == false
    assert compact.pilot_analysis.outcome.outcome == :recommended
    assert compact.final_result.family_id == context.definition.family.id
    assert compact.final_result.family_size == length(context.definition.family.comparisons)
    assert Repo.aggregate(StudyResult, :count, :id) == 1
  end

  test "STUDY-JOURNEY-02: WHEN a valid study produces an insufficient Pilot, THE public API SHALL reject :recommended, accept the declared override, complete Final analysis, and return one compact result with pilot_override true",
       context do
    Store.put(:pilot_result, {:ok, insufficient()})

    assert {:ok, %StudyExecution{state: :collecting_pilot} = started} =
             Evaluations.start_study(context.revision.id)

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :awaiting_final}} = Evaluations.study_status(started.id)

    assert {:error, %StudyError{issues: [%{"code" => "invalid_final_selection"}]}} =
             Evaluations.resume_study(started.id, :recommended)

    assert {:ok, %StudyExecution{state: :awaiting_final}} = Evaluations.study_status(started.id)

    assert {:ok, %StudyExecution{state: :collecting_final}} =
             Evaluations.resume_study(
               started.id,
               {:override_insufficient, context.candidate.id}
             )

    await_coordinator(started.id)

    assert {:ok, %StudyExecution{state: :succeeded}} = Evaluations.study_status(started.id)

    assert {:ok, %CompactResult{} = compact} = Evaluations.study_result(started.id)

    assert compact.selection.candidate_id == context.candidate.id
    assert compact.selection.pilot_override == true
    assert compact.pilot_analysis.outcome.outcome == :insufficient
    assert Repo.aggregate(StudyResult, :count, :id) == 1
  end

  # The coordinator owns the activation boundary: it registers the execution
  # before the first workflow call and exits after the last commit. Monitoring
  # that process therefore waits for the committed work without polling.
  defp await_coordinator(execution_id) do
    case Registry.lookup(NetworkDefense.Evaluation.Study.CoordinatorRegistry, execution_id) do
      [{pid, _value}] ->
        reference = Process.monitor(pid)
        assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, @coordinator_timeout

      [] ->
        :ok
    end
  end

  defp install_workflow_boundaries! do
    for module <- @workflow_modules do
      :meck.new(module, [:passthrough, :no_link])
      :meck.expect(module, :dispatch, fn _run_id -> :ok end)
    end

    :meck.expect(CollectionWorkflow, :create, &collect_pilot!/1)

    :meck.expect(CollectionWorkflow, :await, fn _run_id ->
      {:ok, Store.get(:pilot_snapshot_id)}
    end)

    :meck.expect(PilotWorkflow, :create, fn _params -> {:ok, 802} end)
    :meck.expect(PilotWorkflow, :await, fn _run_id -> {:ok, :succeeded} end)
    :meck.expect(PilotWorkflow, :result, fn _run_id -> Store.get(:pilot_result) end)

    :meck.expect(FinalCollectionWorkflow, :create, fn _phase -> {:ok, 902} end)

    :meck.expect(FinalCollectionWorkflow, :await, fn _run_id ->
      {:ok, Store.get(:final_snapshot_id)}
    end)

    :meck.expect(FinalWorkflow, :create, &prepare_final_result/1)
    :meck.expect(FinalWorkflow, :await, fn _run_id -> {:ok, :succeeded} end)
    :meck.expect(FinalWorkflow, :result, fn _run_id -> {:ok, Store.get(:final_result)} end)

    on_exit(fn -> Enum.each(@workflow_modules, &:meck.unload/1) end)
  end

  defp collect_pilot!(phase) do
    execution = Repo.get!(StudyExecution, phase.execution_id)
    definition = Store.get(:definition)
    items = StudyFixtures.collect_pilot_items(execution, phase, definition)

    {:ok, snapshot_id} =
      PilotSnapshot.assemble_and_store_pilot_snapshot(phase, items, definition)

    Store.put(:pilot_snapshot_id, snapshot_id)
    {:ok, 801}
  end

  defp prepare_final_result(params) do
    with {:ok, %FinalRequest{} = request} <- FinalRequest.parse(params) do
      Store.put(:final_result, FinalConformance.result!(request, Store.get(:final_fixture)))
      {:ok, 903}
    end
  end

  defp recommended(candidate) do
    %PilotResult{
      outcome: "recommended",
      recommendation: %Recommendation{
        candidate_id: candidate.id,
        plan_count: candidate.plan_count_per_side,
        attacks_per_plan: candidate.attacks_per_plan
      }
    }
  end

  defp insufficient do
    %PilotResult{outcome: "insufficient", insufficient_reason: "no_passing_candidate"}
  end
end
