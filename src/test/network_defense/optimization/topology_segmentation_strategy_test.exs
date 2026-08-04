defmodule NetworkDefense.Optimization.TopologySegmentationStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.BlockReachability
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, Service}
  alias NetworkDefense.Optimization.{Strategy, TopologySegmentationStrategy}
  alias NetworkDefense.Relationships.{NetworkReachability, Runs}

  test "new/2 accepts an operational graph with reachability edges" do
    {graph, source} = graph()

    assert {:ok, %TopologySegmentationStrategy{}} =
             TopologySegmentationStrategy.new(graph, simulation_params(source))
  end

  test "new/2 rejects a canonical graph without reachability edges" do
    source = host("source")
    app = host("app")
    app_service = service("app-service")

    graph =
      GraphFixtures.graph(
        [source, app, app_service],
        [GraphFixtures.edge("runs-app", app, app_service, Runs)]
      )

    assert {:error, "topology segmentation requires reachability relationships in the graph"} =
             TopologySegmentationStrategy.new(graph, simulation_params(source))
  end

  test "ranks the reachability block that disconnects the most hosts from the foothold" do
    {graph, source} = graph()

    assert [
             %BlockReachability{edge_id: "ingress"},
             %BlockReachability{edge_id: "gateway-app"},
             %BlockReachability{edge_id: "gateway-database"}
           ] =
             Strategy.rank(
               %TopologySegmentationStrategy{initial_foothold_node_id: source.id},
               [BlockReachability],
               graph,
               3
             )
  end

  test "does not rank another action type" do
    {graph, source} = graph()

    assert Strategy.rank(
             %TopologySegmentationStrategy{initial_foothold_node_id: source.id},
             [],
             graph,
             1
           ) == []
  end

  defp graph do
    source = host("source")
    gateway = host("gateway")
    app = host("app")
    database = host("database")
    ingress_service = service("ingress-service")
    app_service = service("app-service")
    database_service = service("database-service")

    graph =
      GraphFixtures.graph(
        [
          source,
          gateway,
          app,
          database,
          ingress_service,
          app_service,
          database_service
        ],
        [
          GraphFixtures.edge("ingress", source, ingress_service, NetworkReachability),
          GraphFixtures.edge("runs-ingress", gateway, ingress_service, Runs),
          GraphFixtures.edge("gateway-app", gateway, app_service, NetworkReachability),
          GraphFixtures.edge("runs-app", app, app_service, Runs),
          GraphFixtures.edge("gateway-database", gateway, database_service, NetworkReachability),
          GraphFixtures.edge("runs-database", database, database_service, Runs)
        ]
      )

    {graph, source}
  end

  defp simulation_params(source) do
    %{
      simulation_params: %{
        monte_carlo_trials: 1,
        iterations_per_run: 1,
        initial_foothold_node_id: source.id,
        generate_seed: true,
        max_attempts: 1
      }
    }
  end

  defp host(id), do: GraphFixtures.node(id, Host, %{"name" => id})

  defp service(id),
    do: GraphFixtures.node(id, Service, %{"name" => id, "protocol" => "tcp", "port" => 443})
end
