defmodule NetworkDefense.SimulationsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.{Graph, Node}
  alias NetworkDefense.Simulation.Contracts.SimulationParams
  alias NetworkDefense.Simulations

  test "broadcasts a correlated failure when execution fails" do
    graph = %{Graph.new("invalid graph") | nodes: [%Node{type: nil}]}
    correlation_id = Ecto.UUID.generate()

    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

    assert {:ok, _pid} =
             Simulations.run_async(graph, correlation_id, %SimulationParams{
               monte_carlo_trials: 1,
               iterations_per_run: 1,
               initial_foothold_node_id: "invalid"
             })

    assert_receive {:simulation_failed,
                    %{correlation_id: ^correlation_id, graph_id: graph_id, reason: reason}},
                   5_000

    assert graph_id == graph.id
    assert reason =~ "initial foothold must identify a host"
  end
end
