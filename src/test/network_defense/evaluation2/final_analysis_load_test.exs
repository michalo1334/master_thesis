defmodule NetworkDefense.Evaluation2.FinalAnalysisLoadTest do
  @moduledoc """
  Load and run-binding checks of the Final analysis phase.

  Gust parses the DAG source and links its declared tasks, so a load proves that
  the source, the action modules, the mapped stage, and the downstream chain are
  acceptable to the runner.

  The binding cases then store one real analysis phase run and one accepted Final
  snapshot through the existing transaction owners, and prove that a task acts
  only for its own run, its own phase, and its own execution evidence. The
  failure cases of the tasks need the same stored records, because a task fails
  permanently only after it binds its run.

  The cases need the isolated local test database for the Gust and study rows.

      mix test test/network_defense/evaluation2/final_analysis_load_test.exs
  """

  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Definition
  alias Gust.DAG.Loader.Worker, as: DAGLoader
  alias Gust.Flows
  alias NetworkDefense.Evaluation2.Study.{Evidence, Persistence}
  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Final.AnalysisContract.Input
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.Actions.{
    Boundary,
    Correct,
    Evaluate
  }

  alias NetworkDefense.Evaluation2Test.FinalFixtures

  @moduletag :integration
  @moduletag case_id: "BIND-02"

  @dag_name "evaluation2_study_final_analysis"
  @terminal "correct_final_family"

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    start_supervised!({DAGLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})

    # The synchronous read follows the loader's bootstrap continuation.
    DAGLoader.get_definitions()
    :ok
  end

  test "the Final analysis DAG loads as one preparation, mapped evaluation, and correction chain" do
    dag = Flows.get_dag_by_name(@dag_name)
    assert %Flows.Dag{id: dag_id} = dag

    assert {:ok, %Definition{} = definition} = DAGLoader.get_definition(dag_id)
    assert Definition.empty_errors?(definition)

    tasks = definition.tasks
    assert map_size(tasks) == 3

    assert tasks["prepare_final_analysis"][:store_result] == true

    assert downstream(tasks, "prepare_final_analysis") == ["evaluate_final_comparison"]

    assert tasks["evaluate_final_comparison"][:map_over] == :prepare_final_analysis
    assert downstream(tasks, "evaluate_final_comparison") == [@terminal]

    assert tasks[@terminal][:store_result] == true
    assert downstream(tasks, @terminal) == []
  end

  describe "run binding" do
    test "a task binds to the accepted snapshot of its own analysis run" do
      %{params: params, run: run, snapshot: snapshot, phase_run: phase_run, execution: execution} =
        analyzing()

      assert {:ok, context} = Boundary.run_context(params, %{run_id: run.id})

      assert context.phase.phase == :final_analysis
      assert context.phase_run.id == phase_run.id
      assert context.input.phase_run_id == phase_run.id
      assert context.input.snapshot_id == snapshot.id
      assert context.execution.id == execution.id
    end

    test "an acting Gust run that does not own the phase run is rejected" do
      %{params: params, run: run} = analyzing()

      assert Boundary.run_context(params, %{run_id: run.id + 1000}) == {:error, :foreign_run}
    end

    test "a phase run of another phase is rejected" do
      %{params: params, run: run} = collection_phase_run()

      assert Boundary.run_context(params, %{run_id: run.id}) == {:error, :foreign_phase}
    end

    test "a snapshot of another execution is rejected" do
      %{params: params, run: run} = analyzing()
      other = analyzing()

      forged = %{params | "study_evidence_snapshot_id" => other.snapshot.id}

      assert Boundary.run_context(forged, %{run_id: run.id}) == {:error, :foreign_snapshot}
    end

    test "the Pilot snapshot of the same execution is rejected" do
      %{params: params, run: run, execution: execution} = analyzing()

      {:ok, pilot_phase} = Persistence.fetch_execution_phase(execution.id, :pilot_collection)

      {:ok, pilot_snapshot} = Persistence.fetch_phase_evidence_snapshot(pilot_phase.id)

      forged = %{params | "study_evidence_snapshot_id" => pilot_snapshot.id}

      assert Boundary.run_context(forged, %{run_id: run.id}) == {:error, :foreign_snapshot}
    end

    test "a task fails permanently when its stored evaluation batch is missing" do
      %{params: params, run: run} = analyzing()

      assert_raise Gust.DAG.NonRecError, fn ->
        Correct.execute([params: params], %{run_id: run.id})
      end
    end

    test "a mapped evaluation fails permanently when the capability rejects its job" do
      %{params: params, run: run} = analyzing()

      assert_raise Gust.DAG.NonRecError, fn ->
        Evaluate.execute(
          [params: params, job: %{"comparison_position" => 99}],
          %{run_id: run.id}
        )
      end
    end
  end

  describe "stored evaluation batch" do
    test "the prepared and evaluated positions must agree" do
      %{run: run} = analyzing()
      store_preparation(run, [0, 1])
      store_evaluations(run, [0, 1])

      assert {:ok, statistics} = Boundary.stored_statistics(run.id)
      assert Enum.map(statistics, & &1.estimate.value) == [0.2, 1.2]
    end

    test "an evaluation of another comparison is rejected" do
      %{run: run} = analyzing()
      store_preparation(run, [0, 1])
      store_evaluations(run, [0, 1, 2])

      assert Boundary.stored_statistics(run.id) == {:error, :foreign_comparisons}
    end

    test "a gap in the stored positions is rejected" do
      %{run: run} = analyzing()
      store_preparation(run, [0, 2])
      store_evaluations(run, [0, 2])

      assert Boundary.stored_statistics(run.id) == {:error, :incomplete_evaluations}
    end

    test "an unfinished evaluation row is rejected" do
      %{run: run} = analyzing()
      store_preparation(run, [0])

      {:ok, _task} =
        Flows.create_task(
          task_attrs(run, "evaluate_final_comparison", 0, :running, evaluation(0))
        )

      assert Boundary.stored_statistics(run.id) == {:error, :unfinished_evaluations}
    end

    test "a missing preparation result is rejected" do
      %{run: run} = analyzing()
      store_evaluations(run, [0])

      assert Boundary.stored_statistics(run.id) == {:error, :missing_preparation}
    end
  end

  # One analysis phase run of one approved execution with its accepted Final
  # snapshot. The evidence stays synthetic, because the binding cases never read
  # matrix values.
  defp analyzing do
    context = FinalFixtures.approved_context()

    {:ok, snapshot} =
      Persistence.insert_evidence_snapshot(context.active_phase.id, %Evidence{comparisons: []})

    {:ok, analyzing} = Executions.accept_final_collection(context.active_phase.id)

    phase_run_id = Ecto.UUID.generate()

    {:ok, run} =
      Flows.create_run(%{
        dag_id: dag_id(),
        params:
          AnalysisContract.to_params(%Input{
            phase_run_id: phase_run_id,
            snapshot_id: snapshot.id
          })
      })

    {:ok, phase_run} =
      Persistence.link_phase_run(analyzing.active_phase.id, :single, phase_run_id, run.id)

    %{
      execution: analyzing.execution,
      snapshot: snapshot,
      phase_run: phase_run,
      run: run,
      params: run.params
    }
  end

  # One phase run of the Final collection phase, so the phase check has a real
  # foreign phase run to reject.
  defp collection_phase_run do
    context = FinalFixtures.approved_context()
    phase_run_id = Ecto.UUID.generate()

    {:ok, run} =
      Flows.create_run(%{
        dag_id: dag_id(),
        params:
          AnalysisContract.to_params(%Input{
            phase_run_id: phase_run_id,
            snapshot_id: Ecto.UUID.generate()
          })
      })

    {:ok, phase_run} =
      Persistence.link_phase_run(context.active_phase.id, :single, phase_run_id, run.id)

    %{phase_run: phase_run, run: run, params: run.params}
  end

  defp dag_id do
    %Flows.Dag{id: dag_id} = Flows.get_dag_by_name(@dag_name)
    dag_id
  end

  defp store_preparation(run, positions) do
    items = Enum.map(positions, &%{"comparison_position" => &1})

    # Gust stores a list result of a preparation task under `gust_task_items`,
    # because the mapped stage expands one task per entry.
    {:ok, _task} =
      Flows.create_task(
        task_attrs(run, "prepare_final_analysis", nil, :succeeded, %{
          "gust_task_items" => items
        })
      )
  end

  defp store_evaluations(run, positions) do
    Enum.each(positions, fn position ->
      {:ok, _task} =
        Flows.create_task(
          task_attrs(run, "evaluate_final_comparison", position, :succeeded, evaluation(position))
        )
    end)
  end

  defp task_attrs(run, name, map_index, status, result) do
    %{
      run_id: run.id,
      name: name,
      map_index: map_index,
      status: status,
      result: result,
      error: %{},
      params: %{}
    }
  end

  # One stored evaluation result. The values illustrate the transport shape; the
  # scientific content belongs to the analysis capability.
  defp evaluation(position) do
    %{
      "comparison_position" => position,
      "statistics" => %{
        "method" => "matching_bounded_mean_v1",
        "estimate" => %{"contrast" => "alternative_minus_reference", "value" => 0.2 + position},
        "interval" => %{"confidence_level" => 0.95, "lower" => 0.05, "upper" => 0.4},
        "test" => %{
          "method" => "sign_conservative_betting",
          "alternative" => "two_sided",
          "raw_p_value" => 0.04
        },
        "assessment" => %{"status" => "informative", "warnings" => []}
      }
    }
  end

  defp downstream(tasks, name) do
    tasks |> Map.fetch!(name) |> Map.fetch!(:downstream) |> Enum.sort()
  end
end
