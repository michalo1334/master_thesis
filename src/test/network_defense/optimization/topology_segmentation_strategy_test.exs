defmodule NetworkDefense.Optimization.TopologySegmentationStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.BlockSegmentReachability
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, NetworkSegment, Service}
  alias NetworkDefense.Optimization.{Strategy, TopologySegmentationStrategy}
  alias NetworkDefense.Relationships.{Contains, Runs, SegmentReachability}

  test "new/2 accepts a canonical graph with segment policy edges" do
    {graph, source} = graph()

    assert {:ok, %TopologySegmentationStrategy{}} =
             TopologySegmentationStrategy.new(graph, simulation_params(source))
  end

  test "new/2 rejects a canonical graph without segment policy edges" do
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

  test "ranks canonical policy edges by marginal reachable-host reduction" do
    {graph, source} = graph()

    assert [
             %BlockSegmentReachability{edge_id: "ingress"},
             %BlockSegmentReachability{edge_id: "gateway-app"},
             %BlockSegmentReachability{edge_id: "gateway-database"}
           ] =
             rank(graph, source.id)
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

  test "excludes overlapping policies whose removal leaves flows intact" do
    ext_segment = segment("ext-segment")
    int_segment = segment("int-segment")
    internet = host("internet")
    dmz = host("dmz")
    https = service("https")

    graph =
      GraphFixtures.graph(
        [ext_segment, int_segment, internet, dmz, https],
        [
          GraphFixtures.edge("contains-internet", ext_segment, internet, Contains),
          GraphFixtures.edge("contains-dmz", int_segment, dmz, Contains),
          GraphFixtures.edge("runs-https", dmz, https, Runs),
          GraphFixtures.edge("ingress-any", ext_segment, int_segment, SegmentReachability, %{
            "protocol" => "any"
          }),
          GraphFixtures.edge("ingress-tcp", ext_segment, int_segment, SegmentReachability, %{
            "protocol" => "tcp"
          })
        ]
      )

    assert rank(graph, internet.id) == []
  end

  test "ranks a self policy that enables same-segment flows" do
    lan_segment = segment("lan-segment")
    admin = host("admin")
    database = host("database")
    postgres = service("postgres")

    graph =
      GraphFixtures.graph(
        [lan_segment, admin, database, postgres],
        [
          GraphFixtures.edge("contains-admin", lan_segment, admin, Contains),
          GraphFixtures.edge("contains-database", lan_segment, database, Contains),
          GraphFixtures.edge("runs-postgres", database, postgres, Runs),
          GraphFixtures.edge("lan-self", lan_segment, lan_segment, SegmentReachability, %{
            "protocol" => "tcp"
          })
        ]
      )

    assert [%BlockSegmentReachability{edge_id: "lan-self"}] = rank(graph, admin.id)
  end

  test "ranks an upstream directed-path policy above a downstream one" do
    a_segment = segment("a-segment")
    b_segment = segment("b-segment")
    c_segment = segment("c-segment")
    a = host("a")
    b = host("b")
    c = host("c")
    b_service = service("b-service")
    c_service = service("c-service")

    graph =
      GraphFixtures.graph(
        [a_segment, b_segment, c_segment, a, b, c, b_service, c_service],
        [
          GraphFixtures.edge("contains-a", a_segment, a, Contains),
          GraphFixtures.edge("contains-b", b_segment, b, Contains),
          GraphFixtures.edge("contains-c", c_segment, c, Contains),
          GraphFixtures.edge("runs-b", b, b_service, Runs),
          GraphFixtures.edge("runs-c", c, c_service, Runs),
          GraphFixtures.edge("ab", a_segment, b_segment, SegmentReachability, %{
            "protocol" => "tcp"
          }),
          GraphFixtures.edge("bc", b_segment, c_segment, SegmentReachability, %{
            "protocol" => "tcp"
          })
        ]
      )

    assert [%BlockSegmentReachability{edge_id: "ab"}, %BlockSegmentReachability{edge_id: "bc"}] =
             rank(graph, a.id)
  end

  test "orders equal reductions deterministically by edge id" do
    s_segment = segment("s-segment")
    t1_segment = segment("t1-segment")
    t2_segment = segment("t2-segment")
    s = host("s")
    t1 = host("t1")
    t2 = host("t2")
    svc1 = service("svc1")
    svc2 = service("svc2")

    graph =
      GraphFixtures.graph(
        [s_segment, t1_segment, t2_segment, s, t1, t2, svc1, svc2],
        [
          GraphFixtures.edge("contains-s", s_segment, s, Contains),
          GraphFixtures.edge("contains-t1", t1_segment, t1, Contains),
          GraphFixtures.edge("contains-t2", t2_segment, t2, Contains),
          GraphFixtures.edge("runs-svc1", t1, svc1, Runs),
          GraphFixtures.edge("runs-svc2", t2, svc2, Runs),
          GraphFixtures.edge("b-policy", s_segment, t1_segment, SegmentReachability, %{
            "protocol" => "tcp"
          }),
          GraphFixtures.edge("a-policy", s_segment, t2_segment, SegmentReachability, %{
            "protocol" => "tcp"
          })
        ]
      )

    assert [
             %BlockSegmentReachability{edge_id: "a-policy"},
             %BlockSegmentReachability{edge_id: "b-policy"}
           ] =
             rank(graph, s.id)
  end

  defp rank(graph, foothold_id) do
    Strategy.rank(
      %TopologySegmentationStrategy{initial_foothold_node_id: foothold_id},
      [BlockSegmentReachability],
      graph,
      3
    )
  end

  defp graph do
    source = host("source")
    gateway = host("gateway")
    app = host("app")
    database = host("database")
    source_segment = segment("source-segment")
    gateway_segment = segment("gateway-segment")
    app_segment = segment("app-segment")
    database_segment = segment("database-segment")
    ingress_service = service("ingress-service")
    app_service = service("app-service")
    database_service = service("database-service")

    graph =
      GraphFixtures.graph(
        [
          source_segment,
          gateway_segment,
          app_segment,
          database_segment,
          source,
          gateway,
          app,
          database,
          ingress_service,
          app_service,
          database_service
        ],
        [
          GraphFixtures.edge("contains-source", source_segment, source, Contains),
          GraphFixtures.edge("contains-gateway", gateway_segment, gateway, Contains),
          GraphFixtures.edge("contains-app", app_segment, app, Contains),
          GraphFixtures.edge("contains-database", database_segment, database, Contains),
          GraphFixtures.edge(
            "ingress",
            source_segment,
            gateway_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          ),
          GraphFixtures.edge(
            "gateway-app",
            gateway_segment,
            app_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          ),
          GraphFixtures.edge(
            "gateway-database",
            gateway_segment,
            database_segment,
            SegmentReachability,
            %{"protocol" => "tcp"}
          ),
          GraphFixtures.edge("runs-ingress", gateway, ingress_service, Runs),
          GraphFixtures.edge("runs-app", app, app_service, Runs),
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

  defp segment(id), do: GraphFixtures.node(id, NetworkSegment, %{"name" => id})

  defp service(id),
    do: GraphFixtures.node(id, Service, %{"name" => id, "protocol" => "tcp", "port" => 443})
end
