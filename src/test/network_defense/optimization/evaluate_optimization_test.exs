defmodule Mix.Tasks.Evaluate.OptimizationTest do
  use NetworkDefense.DataCase, async: true

  import ExUnit.CaptureIO

  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.GraphFixtures
  alias Mix.Tasks.Evaluate.Optimization

  @revision_id Ecto.UUID.generate()

  test "builds a valid cvss request without simulation params" do
    assert {:ok, request} =
             Optimization.build_request(
               strategy: "cvss",
               budget: 2,
               graph_revision_id: @revision_id
             )

    assert request.graph_revision_id == @revision_id
    assert request.correlation_id =~ ~r/^[0-9a-f-]{36}$/
    assert request.optimization_params.strategy == "cvss"
    assert request.optimization_params.budget == 2
    assert request.optimization_params.simulation_params == nil
  end

  test "builds a valid simulated annealing request with simulation args" do
    assert {:ok, request} =
             Optimization.build_request(
               strategy: "simulated_annealing",
               budget: 2,
               graph_revision_id: @revision_id,
               trials: 20,
               iterations: 10,
               initial_foothold: "host-1",
               max_attempts: 3,
               seed: 42
             )

    params = request.optimization_params.simulation_params
    assert params.monte_carlo_trials == 20
    assert params.iterations_per_run == 10
    assert params.initial_foothold_node_id == "host-1"
    assert params.max_attempts == 3
    assert params.seed == 42
    assert params.generate_seed == false
  end

  test "defaults generate_seed to true and max_attempts to 1 without a seed" do
    assert {:ok, request} =
             Optimization.build_request(
               strategy: "simulated_annealing",
               budget: 2,
               graph_revision_id: @revision_id,
               trials: 20,
               iterations: 10,
               initial_foothold: "host-1"
             )

    params = request.optimization_params.simulation_params
    assert params.seed == nil
    assert params.generate_seed == true
    assert params.max_attempts == 1
  end

  test "rejects a missing strategy" do
    assert {:error, reason} =
             Optimization.build_request(budget: 2, graph_revision_id: @revision_id)

    assert reason =~ "--strategy"
  end

  test "rejects a missing budget" do
    assert {:error, reason} =
             Optimization.build_request(strategy: "cvss", graph_revision_id: @revision_id)

    assert reason =~ "--budget"
  end

  test "rejects an unknown strategy" do
    assert {:error, reason} =
             Optimization.build_request(
               strategy: "bogus",
               budget: 2,
               graph_revision_id: @revision_id
             )

    assert reason =~ "invalid"
  end

  test "rejects a negative budget" do
    assert {:error, reason} =
             Optimization.build_request(
               strategy: "cvss",
               budget: -1,
               graph_revision_id: @revision_id
             )

    assert reason =~ "greater than"
  end

  test "rejects a malformed graph revision id" do
    assert {:error, reason} =
             Optimization.build_request(strategy: "cvss", budget: 2, graph_revision_id: "nope")

    assert reason =~ "is invalid"
  end

  test "rejects a simulation strategy without simulation args" do
    assert {:error, reason} =
             Optimization.build_request(
               strategy: "simulated_annealing",
               budget: 2,
               graph_revision_id: @revision_id
             )

    assert reason =~ "can't be blank"
  end

  test "runs synchronously and emits a reproducible JSON record" do
    assert {:ok, graph} = Graphs.insert(graph_with_credential())

    args = [
      "--graph-revision-id",
      graph.revision_id,
      "--strategy",
      "cvss",
      "--budget",
      "1"
    ]

    stdout = capture_io(fn -> Optimization.run(args) end)

    assert %{"status" => "completed", "graph_revision_id" => revision_id} = Jason.decode!(stdout)
    assert revision_id == graph.revision_id

    output = Path.join(System.tmp_dir!(), "optimization-#{Ecto.UUID.generate()}.json")
    on_exit(fn -> File.rm(output) end)

    capture_io(fn -> Optimization.run(args ++ ["--output", output]) end)

    assert %{"status" => "completed", "graph_revision_id" => output_revision_id} =
             output |> File.read!() |> Jason.decode!()

    assert output_revision_id == graph.revision_id
  end

  defp graph_with_credential,
    do: GraphFixtures.persisted_credential_graph("evaluation-runner-test")
end
