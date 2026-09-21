defmodule NetworkDefense.Simulation.SimulationOperationTest do
  use NetworkDefense.DataCase, async: true

  import Ecto.Query
  import NetworkDefense.GraphFixtures

  alias NetworkDefense.Graph.{Graph, Graphs}
  alias NetworkDefense.Nodes.{Host, NetworkSegment}
  alias NetworkDefense.Repo
  alias NetworkDefense.Relationships.Contains
  alias NetworkDefense.Simulation.{Experiment, Experiments, Run, SimulationOperation}

  test "scatters weighted trial ranges and rejects completed trials" do
    experiment =
      Experiment.new(
        graph_revision_id: Ecto.UUID.generate(),
        master_seed: 23,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 3
      )

    assert [{{id, 1, 3}, 3, %{experiment_id: experiment_id, trial_indexes: 1..3}}] =
             experiment |> SimulationOperation.scatter() |> Enum.to_list()

    assert id == experiment.id
    assert experiment_id == experiment.id

    assert_raise RuntimeError, "scatter-gather requires an empty experiment", fn ->
      SimulationOperation.scatter(%{experiment | completed_trials: 1})
    end
  end

  test "keeps trial partitions small enough for bounded result envelopes" do
    experiment =
      Experiment.new(
        graph_revision_id: Ecto.UUID.generate(),
        master_seed: 41,
        iteration_count: 2,
        max_attempts: 1,
        total_trials: 63
      )

    partitions = experiment |> SimulationOperation.scatter() |> Enum.to_list()

    assert Enum.sum_by(partitions, &elem(&1, 1)) == experiment.total_trials
    assert Enum.all?(partitions, &(elem(&1, 1) <= 30))

    assert partitions
           |> Enum.flat_map(fn {_key, _weight, %{trial_indexes: range}} ->
             Enum.to_list(range)
           end) ==
             Enum.to_list(1..experiment.total_trials)
  end

  test "executes a partition sequentially and gathers its runs atomically" do
    {graph, foothold} = persisted_host_graph()

    experiment =
      experiment(
        graph: graph,
        initial_foothold_node_id: foothold.id,
        total_trials: 2
      )

    assert {:ok, runs} =
             SimulationOperation.execute(fn ->
               %{experiment_id: experiment.id, trial_indexes: 1..2}
             end)

    assert Enum.map(runs, & &1.trial_index) == [1, 2]
    assert Enum.all?(runs, &is_nil(&1.graph))
    assert Enum.all?(runs, &(&1.rules == []))

    assert {:ok, %{status: :completed, completed_trials: 2}} =
             SimulationOperation.gather([{{experiment.id, 1, 2}, runs}], experiment, %{
               compute_duration_ms: 4
             })

    assert 2 ==
             Repo.aggregate(from(run in Run, where: run.experiment_id == ^experiment.id), :count)
  end

  defp experiment(opts) do
    graph = Keyword.fetch!(opts, :graph)

    Experiment.new(
      graph: graph,
      master_seed: 23,
      iteration_count: 1,
      max_attempts: 1,
      total_trials: Keyword.get(opts, :total_trials, 3),
      initial_foothold_node_id: Keyword.get(opts, :initial_foothold_node_id)
    )
    |> Experiments.create()
    |> elem(1)
  end

  defp persisted_host_graph do
    graph = Graph.new("Operation graph")
    segment = build_node(graph, NetworkSegment, %{"name" => "segment"})
    foothold = build_node(graph, Host, %{"name" => "foothold"})

    assert {:ok, graph} =
             graph
             |> Graph.add_node(segment)
             |> Graph.add_node(foothold)
             |> Graph.add_edge(edge(Ecto.UUID.generate(), segment, foothold, Contains))
             |> Graphs.insert()

    {graph, foothold}
  end
end
