defmodule NetworkDefense.EvaluationProgressTest do
  use NetworkDefense.DataCase, async: false

  alias NetworkDefense.Evaluation
  alias NetworkDefense.EvaluationFixtures
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.Seed

  setup do
    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Evaluation.evaluation_events_topic())
    :ok
  end

  test "emits valid ordered progress across plan selection and attack trials" do
    id = "progress-#{System.unique_integer([:positive])}"
    assert {:ok, _} = save_manifest(id)

    assert {:ok, run} = Evaluation.start(id)
    assert {:ok, %{status: "completed"}} = Evaluation.run(run.id)

    payloads = collect_progress(run.id)

    assert [_, _, _, _ | _] = payloads

    first = hd(payloads)
    assert first.completed == 0
    assert first.total == 2 + 3 * 3
    assert first.correlation_id == run.id
    assert first.graph_revision_id == run.source_graph_revision_id

    completed = Enum.map(payloads, & &1.completed)
    assert completed == Enum.sort(completed)
    assert Enum.max(completed) == first.total

    assert Enum.all?(payloads, &(&1.correlation_id == run.id))
    assert Enum.all?(payloads, &is_binary(&1.detail))
    assert Enum.all?(payloads, &(&1.graph_id == first.graph_id))
    assert Enum.all?(payloads, &is_binary(&1.graph_revision_id))

    assert Enum.any?(payloads, &String.starts_with?(&1.detail, "Selected plan"))
    assert Enum.any?(payloads, &String.starts_with?(&1.detail, "Baseline attack trials"))
    assert Enum.any?(payloads, &String.starts_with?(&1.detail, "Post-defense attack trials"))
  end

  test "emits meaningful progress for work done after resume" do
    id = "resume-#{System.unique_integer([:positive])}"
    assert {:ok, _} = save_manifest(id)

    assert {:ok, run} = Evaluation.start(id)

    entry_host_id = get_in(run.resolved_manifest, ["attacker", "entry_host", "value"])

    {:ok, baseline} =
      Experiments.create(
        Experiment.new(
          graph_revision_id: run.source_graph_revision_id,
          evaluation_run_id: run.id,
          optimization_run_id: nil,
          master_seed: Seed.child_seed(9001, 3),
          iteration_count: 1,
          max_attempts: 1,
          total_trials: 3,
          completed_trials: 3,
          initial_foothold_node_id: entry_host_id
        )
      )

    assert {:ok, %{status: "completed"}} = Experiments.complete(baseline)

    assert {:ok, %{status: "completed"}} = Evaluation.run(run.id)

    payloads = collect_progress(run.id)

    assert [_, _, _ | _] = payloads

    first = hd(payloads)
    assert first.completed == 0
    assert first.total == 2 + 3 * 3

    completed = Enum.map(payloads, & &1.completed)
    assert completed == Enum.sort(completed)
    assert Enum.max(completed) == first.total
    assert Enum.all?(payloads, &(&1.correlation_id == run.id))
  end

  defp save_manifest(id) do
    EvaluationFixtures.save_manifest(id, EvaluationFixtures.analysis_manifest())
  end

  defp collect_progress(run_id), do: collect_progress(run_id, [])

  defp collect_progress(run_id, acc) do
    receive do
      {:evaluation_progress, %{correlation_id: ^run_id} = payload} ->
        collect_progress(run_id, [payload | acc])
    after
      100 -> Enum.reverse(acc)
    end
  end
end
