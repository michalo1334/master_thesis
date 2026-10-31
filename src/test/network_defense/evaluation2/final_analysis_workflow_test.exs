defmodule NetworkDefense.Evaluation2.FinalAnalysisWorkflowTest do
  use NetworkDefense.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Loader.Worker, as: DAGLoader
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Final.Analysis
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2.Study.Persistence.Result
  alias NetworkDefense.Evaluation2.Study.Workflow
  alias NetworkDefense.Evaluation2Test.FinalFixtures

  @moduletag :integration
  @moduletag case_id: "FLOW-05/RESULT-01/BIND-01/BIND-02"
  @moduletag timeout: 60_000

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    previous = Application.get_env(:network_defense, :measured_environment_revision)

    Application.put_env(
      :network_defense,
      :measured_environment_revision,
      "final-analysis-workflow"
    )

    on_exit(fn ->
      Sandbox.stop_owner(owner)

      if previous,
        do: Application.put_env(:network_defense, :measured_environment_revision, previous),
        else: Application.delete_env(:network_defense, :measured_environment_revision)
    end)

    start_supervised!({DAGLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})
    DAGLoader.get_definitions()
    %{context: FinalFixtures.approved_context()}
  end

  test "FLOW-05/RESULT-01 WHEN native Final analysis completes THEN result and success SHALL persist once",
       c do
    id = c.context.execution.id
    assert {:error, %{issues: [%{code: "result_not_available"}]}} = Study.result(id)
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    assert {:ok, %{state: :succeeded}} = Study.continue(id)
    assert {:ok, result} = Study.result(id)
    assert result.execution_id == id
    assert result.revision.study_id == c.context.revision.study_id
    assert result.selection == c.context.execution.selection
    assert result.pilot_outcome == c.context.execution.pilot_outcome
    assert Enum.map(result.family.comparisons, & &1.identity.tier) == [:small, :medium, :large]
    assert {:ok, phase} = Persistence.fetch_execution_phase(id, :final_analysis)
    assert {:ok, [run]} = Persistence.list_phase_runs(phase.id)
    assert {:ok, output} = Workflow.final_analysis_result(run.id)
    assert :ok = Analysis.validate_output(c.context.revision.definition, output)
    assert {:ok, timing} = Workflow.final_timing(id)
    assert result.timing == timing
    assert {:ok, stored} = Persistence.fetch_result(id)
    assert stored.family == output.family_result

    # Re-entry uses the same canonical result, including concurrent acceptance.
    repeats =
      for _ <- 1..2,
          do:
            Task.async(fn ->
              Executions.accept_final_analysis(phase.id, output.family_result, timing)
            end)

    for repeat <- repeats,
        do: assert({:ok, %{execution: %{state: :succeeded}}} = Task.await(repeat))

    assert {:ok, %{state: :succeeded}} = Study.continue(id)
    assert {:ok, ^result} = Study.result(id)
    assert Repo.aggregate(from(r in Result, where: r.study_execution_id == ^id), :count) == 1

    [first | rest] = output.family_result.comparisons

    different = %{
      output.family_result
      | comparisons: [
          %{
            first
            | adjustment: %{first.adjustment | reject_null: not first.adjustment.reject_null}
          }
          | rest
        ]
    }

    assert {:error, _} = Executions.accept_final_analysis(phase.id, different, timing)
    assert {:ok, ^result} = Study.result(id)
  end

  test "BIND-02 WHEN an accepted run input or terminal is foreign THEN completion SHALL be rejected",
       c do
    id = c.context.execution.id
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    assert {:ok, %{state: :succeeded}} = Study.continue(id)
    {:ok, phase} = Persistence.fetch_execution_phase(id, :final_analysis)
    {:ok, canonical} = Persistence.fetch_phase_run(phase.id, :single)
    run = Gust.Repo.get!(Gust.Flows.Run, canonical.gust_run_id)
    foreign = Map.put(run.params, "study_evidence_snapshot_id", Ecto.UUID.generate())
    changed = Gust.Repo.update!(Ecto.Changeset.change(run, params: foreign))
    assert {:error, _} = Workflow.final_analysis_result(canonical.id)
    Gust.Repo.update!(Ecto.Changeset.change(changed, params: run.params))
    assert {:ok, _} = Workflow.final_analysis_result(canonical.id)

    [terminal] = Gust.Flows.get_tasks_by_name("correct_final_family", run.id)
    Gust.Repo.update!(Ecto.Changeset.change(terminal, result: %{"family_result" => %{}}))
    assert {:error, _} = Workflow.final_analysis_result(canonical.id)
    # Stored public results use the atomic accepted result, not mutable Gust output.
    assert {:ok, _} = Study.result(id)
  end

  test "FLOW-05 WHEN the measurement label changes before acceptance THEN no result SHALL be accepted",
       c do
    :meck.new(Analysis, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Analysis) end)

    :meck.expect(Analysis, :correct, fn snapshot_id, statistics ->
      result = :meck.passthrough([snapshot_id, statistics])

      Application.put_env(
        :network_defense,
        :measured_environment_revision,
        "changed-before-acceptance"
      )

      result
    end)

    id = c.context.execution.id
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    assert {:error, _} = Study.continue(id)
    assert {:ok, %{state: :analyzing_final}} = Study.status(id)
    assert {:error, _} = Study.result(id)
    assert Repo.aggregate(from(r in Result, where: r.study_execution_id == ^id), :count) == 0
    {:ok, phase} = Persistence.fetch_execution_phase(id, :final_analysis)
    {:ok, [canonical]} = Persistence.list_phase_runs(phase.id)

    Application.put_env(
      :network_defense,
      :measured_environment_revision,
      "final-analysis-workflow"
    )

    assert {:ok, %{state: :succeeded}} = Study.continue(id)
    assert {:ok, [^canonical]} = Persistence.list_phase_runs(phase.id)
  end

  test "FLOW-05 WHEN the success transition rejects after insertion THEN the transaction SHALL roll back",
       c do
    alias NetworkDefense.Evaluation2.Study.Lifecycle

    :meck.new(Lifecycle, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Lifecycle) end)

    :meck.expect(Lifecycle, :transition, fn
      :analyzing_final, :final_analyzed -> {:error, :invalid_transition}
      state, event -> :meck.passthrough([state, event])
    end)

    id = c.context.execution.id
    start_supervised!({Gust.Run.DispatcherSupervisor, []})
    assert {:error, _} = Study.continue(id)
    assert {:ok, %{state: :analyzing_final}} = Study.status(id)
    assert Repo.aggregate(from(r in Result, where: r.study_execution_id == ^id), :count) == 0
    assert {:error, _} = Study.result(id)
    {:ok, phase} = Persistence.fetch_execution_phase(id, :final_analysis)
    {:ok, [canonical]} = Persistence.list_phase_runs(phase.id)
    assert {:ok, _} = Workflow.final_analysis_result(canonical.id)

    :meck.expect(Lifecycle, :transition, fn state, event -> :meck.passthrough([state, event]) end)
    assert {:ok, %{state: :succeeded}} = Study.continue(id)
    assert {:ok, [^canonical]} = Persistence.list_phase_runs(phase.id)
    assert {:ok, _} = Study.result(id)
  end

  test "FLOW-05 WHEN encoding or lifecycle acceptance fails THEN no partial result SHALL remain",
       c do
    assert {:error, _} = Executions.accept_final_analysis(c.context.active_phase.id, nil, nil)
    assert {:ok, %{state: :collecting_final}} = Study.status(c.context.execution.id)

    assert Repo.aggregate(
             from(r in Result, where: r.study_execution_id == ^c.context.execution.id),
             :count
           ) == 0
  end
end
