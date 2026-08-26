defmodule NetworkDefense.Topology.FixedOrderFulfilmentScenarioTest do
  use NetworkDefense.DataCase

  alias NetworkDefense.Actions.{Action, ExploitVulnerability}
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, MaterializeReachability}
  alias NetworkDefense.Cvss

  alias NetworkDefense.DefenseActions.{
    BlockSegmentReachability,
    PatchVulnerability
  }

  alias NetworkDefense.Nodes.{
    Credential,
    Host,
    MissionCapability,
    NetworkSegment,
    Service,
    Vulnerability
  }

  alias NetworkDefense.Optimization.{
    CvssStrategy,
    Optimizer,
    SimulationInformedStrategy,
    Strategy,
    TopologySegmentationStrategy
  }

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    Contains,
    HasVulnerability,
    NetworkReachability,
    Runs,
    SegmentReachability,
    StoresCredential,
    Supports
  }

  alias NetworkDefense.Rules.{
    AcquireCredentialRule,
    RemoteServiceExploitation,
    ReuseCredentialRule,
    Rule
  }

  alias NetworkDefense.Simulation.{MissionImpact, Run}
  alias NetworkDefense.Topology.FixedOrderFulfilmentScenario

  test "builds the declared hosts in one segment each" do
    graph = FixedOrderFulfilmentScenario.graph()

    assert Enum.count(Graph.nodes(graph), &(&1.type == Host)) == 80
    assert {:ok, _graph} = Graph.hydrate(graph, Graph.nodes(graph), Graph.edges(graph))

    assert segment_host_counts(graph) == %{
             "Application" => 12,
             "Backup" => 4,
             "Data" => 8,
             "External" => 1,
             "Identity" => 5,
             "Management" => 6,
             "Monitoring" => 4,
             "Partner DMZ" => 3,
             "Public DMZ" => 3,
             "User" => 34
           }

    for host <- Graph.nodes(graph), host.type == Host do
      assert graph
             |> Graph.incoming(host.id)
             |> Enum.count(fn {_segment_id, edge} -> edge.type == Contains end) == 1
    end
  end

  test "uses canonical policies and materializes only declared flows" do
    graph = FixedOrderFulfilmentScenario.graph()

    assert Enum.all?(
             Graph.edges(graph),
             &(&1.type in [
                 Contains,
                 HasVulnerability,
                 Runs,
                 SegmentReachability,
                 Supports,
                 StoresCredential,
                 AuthenticatesTo
               ])
           )

    assert Enum.any?(Graph.edges(graph), &(&1.type == SegmentReachability))
    refute Enum.any?(Graph.edges(graph), &(&1.type == NetworkReachability))

    flows =
      graph
      |> MaterializeReachability.materialize()
      |> Graph.edges()
      |> Enum.filter(&(&1.type == NetworkReachability))
      |> Enum.map(fn edge ->
        {Graph.node(graph, edge.from_id).data.name, Graph.node(graph, edge.to_id).data.name}
      end)

    assert {"internet-entry", "https"} in flows
    assert {"order-gateway", "order-api"} in flows
    refute {"internet-entry", "order-api"} in flows
  end

  test "acquires the order deployment credential and reuses it against the order API" do
    graph = FixedOrderFulfilmentScenario.graph() |> MaterializeReachability.materialize()
    order_gateway = node_by_name(graph, "order-gateway")
    order_service = node_by_name(graph, "order-service")

    credential =
      Enum.find(
        Graph.nodes(graph),
        &(&1.type == Credential and &1.data.identifier == "order-service-deployment-key")
      )

    attacker_state = AttackerState.new(order_gateway.id, :user)

    acquire =
      Rule.evaluate(
        %AcquireCredentialRule{},
        Run.new(graph: graph, initial_attacker_state: attacker_state)
      )
      |> Enum.find(&(&1.credential_id == credential.id))

    assert acquire.credential_id == credential.id
    attacker_state = Action.execute(acquire, attacker_state)

    assert [reuse | _] =
             Rule.evaluate(
               %ReuseCredentialRule{},
               Run.new(graph: graph, initial_attacker_state: attacker_state)
             )

    assert reuse.target_host_id == order_service.id
    assert reuse.granted_privilege == :administrator

    attacker_state = Action.execute(reuse, attacker_state)
    assert order_service.id in AttackerState.foothold_nodes(attacker_state)
    assert AttackerState.privilege_for(attacker_state, order_service.id) == :administrator
  end

  test "requires both order-processing flows for pre-attack feasibility" do
    graph = FixedOrderFulfilmentScenario.graph()
    assert MissionImpact.pre_attack_feasible?(graph)

    assert %{required_flow_count: 2, missing_flow_count: 0} = order_processing_status(graph)

    for policy <- [external_order_gateway_policy(graph), order_api_policy(graph)] do
      assert %{down?: true, missing_flow_count: 1} =
               graph
               |> Graph.remove_edge_by_id(policy.id)
               |> order_processing_status()
    end
  end

  test "topology segmentation keeps required policies unless feasibility is disabled" do
    graph = FixedOrderFulfilmentScenario.graph()
    order_gateway = node_by_name(graph, "order-gateway")

    assert {:ok, strategy} =
             TopologySegmentationStrategy.new(graph, strategy_params(order_gateway))

    constrained = Optimizer.apply(graph, strategy, 1)

    refute Enum.any?(constrained.actions, fn
             %BlockSegmentReachability{edge_id: edge_id} ->
               edge_id in [external_order_gateway_policy(graph).id, order_api_policy(graph).id]

             _ ->
               false
           end)

    unconstrained =
      Optimizer.apply(graph, strategy, 1, require_pre_attack_feasibility: false)

    assert [%BlockSegmentReachability{edge_id: edge_id}] = unconstrained.actions
    assert policy_properties(graph, edge_id) == {"Public DMZ", "Application", 8080}
  end

  test "fixed-seed mission-aware simulation selects an order-route defense" do
    graph = FixedOrderFulfilmentScenario.graph()
    internet_entry = node_by_name(graph, "internet-entry")

    assert {:ok, full} =
             SimulationInformedStrategy.new(
               graph,
               strategy_params(internet_entry, %{objective: :mission_then_blast_radius})
             )

    full_result = Optimizer.apply(graph, full, 1)

    assert [full_action] = full_result.actions
    refute patch_identifier(graph, full_action) == "CVE-2021-44228"
    assert patch_identifier(graph, full_action) == "CVE-2017-9805"
  end

  test "fixed-seed blast-only feasibility variants distinguish public order ingress" do
    graph = FixedOrderFulfilmentScenario.graph()
    order_gateway = node_by_name(graph, "order-gateway")

    assert {:ok, constrained} =
             SimulationInformedStrategy.new(
               graph,
               strategy_params(order_gateway, %{objective: :blast_radius_only})
             )

    assert {:ok, unconstrained} =
             SimulationInformedStrategy.new(
               graph,
               strategy_params(order_gateway, %{
                 objective: :blast_radius_only,
                 require_pre_attack_feasibility: false
               })
             )

    constrained_result = Optimizer.apply(graph, constrained, 1)

    unconstrained_result =
      Optimizer.apply(graph, unconstrained, 1, require_pre_attack_feasibility: false)

    refute constrained_result.actions == unconstrained_result.actions
    assert [] = constrained_result.actions

    refute Enum.any?(constrained_result.actions, fn
             %BlockSegmentReachability{edge_id: edge_id} ->
               edge_id in [external_order_gateway_policy(graph).id, order_api_policy(graph).id]

             _ ->
               false
           end)

    assert [%BlockSegmentReachability{edge_id: edge_id}] = unconstrained_result.actions
    assert policy_properties(graph, edge_id) == {"Public DMZ", "Application", 8080}
  end

  test "keeps customer support operational when one support host is compromised" do
    graph = FixedOrderFulfilmentScenario.graph()
    customer_support = node_by_name(graph, "customer-support-service")

    assert [_, _] =
             graph
             |> Graph.nodes()
             |> Enum.find(&(&1.type == MissionCapability and &1.data.name == "Customer support"))
             |> then(&Graph.supporting_host_ids(graph, &1.id))

    assert %{down?: false, supporting_host_count: 2, min_operational_support: 1} =
             graph
             |> MissionImpact.capability_statuses([customer_support.id])
             |> Enum.find(&(&1.name == "Customer support"))
  end

  test "declares each reviewed CVE on its approved service" do
    graph = FixedOrderFulfilmentScenario.graph()

    assert Enum.map(FixedOrderFulfilmentScenario.vulnerabilities(), & &1.identifier) == [
             "CVE-2021-44228",
             "CVE-2021-42013",
             "CVE-2017-9805"
           ]

    for vulnerability <- FixedOrderFulfilmentScenario.vulnerabilities() do
      node =
        Enum.find(
          Graph.nodes(graph),
          &(&1.type == Vulnerability and &1.data.identifier == vulnerability.identifier)
        )

      assert node.type == Vulnerability

      assert [edge] =
               Graph.incoming(graph, node.id)
               |> Enum.map(&elem(&1, 1))
               |> Enum.filter(&(&1.type == HasVulnerability))

      service = Graph.node(graph, edge.from_id)
      assert service.type == Service
      assert service.data.name == vulnerability.service
      assert service.data.version == vulnerability.version

      assert Enum.any?(Graph.incoming(graph, service.id), fn {host_id, runs} ->
               runs.type == Runs and Graph.node(graph, host_id).data.name == vulnerability.host
             end)
    end
  end

  test "emits the reachable public-service exploits with scenario probabilities" do
    graph = FixedOrderFulfilmentScenario.graph() |> MaterializeReachability.materialize()
    internet_entry = node_by_name(graph, "internet-entry")

    actions =
      Rule.evaluate(
        %RemoteServiceExploitation{},
        Run.new(graph: graph, initial_attacker_state: AttackerState.new(internet_entry.id))
      )

    assert Enum.map(actions, fn action ->
             vulnerability = Graph.node(graph, action.vulnerability_node_id)
             target = Graph.node(graph, action.target_host_id)
             {vulnerability.data.identifier, target.data.name, action.success_probability}
           end)
           |> Enum.sort() == [
             {"CVE-2017-9805", "order-gateway", 0.5},
             {"CVE-2021-42013", "vendor-portal", 0.6},
             {"CVE-2021-44228", "partner-access-gateway", 0.9}
           ]

    assert Enum.all?(actions, &match?(%ExploitVulnerability{}, &1))
  end

  test "CVSS selects Log4j with a one-action patch budget" do
    graph = FixedOrderFulfilmentScenario.graph()

    assert [%PatchVulnerability{edge_id: edge_id} | _] =
             Strategy.rank(%CvssStrategy{}, [PatchVulnerability], graph, 1)

    assert graph
           |> Graph.node(Graph.edge(graph, edge_id).to_id)
           |> then(& &1.data.identifier) == "CVE-2021-44228"
  end

  test "declared NVD mappings match the static evidence and CVSS scores" do
    snapshot = nvd_file!("snapshot.json")
    provenance = nvd_file!("provenance.json")

    assert Enum.map(snapshot["records"], & &1["id"]) ==
             Enum.map(FixedOrderFulfilmentScenario.vulnerabilities(), & &1.identifier)

    for vulnerability <- FixedOrderFulfilmentScenario.vulnerabilities() do
      record = Enum.find(snapshot["records"], &(&1["id"] == vulnerability.identifier))

      assert Map.take(record, ["product", "version", "scenario_cpe"]) == %{
               "product" => vulnerability.product,
               "version" => vulnerability.version,
               "scenario_cpe" => vulnerability.cpe
             }

      assert record["cvss_v3_1"]["base_metrics"] == vulnerability.cvss
      assert record["cvss_v3_1"]["vector"] == vulnerability.cvss_vector
      assert record["cvss_v3_1"]["base_score"] == vulnerability.cvss_base_score
      assert Cvss.base_score(cvss(vulnerability.cvss)) == vulnerability.cvss_base_score
    end

    refute Enum.any?(snapshot["records"], &Map.has_key?(&1, "exploit_probability"))
    assert provenance["feeds"] |> Enum.count(&(&1["zip_sha256"] && &1["content_sha256"])) == 2
  end

  defp segment_host_counts(graph) do
    graph
    |> Graph.nodes()
    |> Enum.filter(&(&1.type == NetworkSegment))
    |> Map.new(fn segment ->
      count =
        graph
        |> Graph.outgoing(segment.id)
        |> Enum.count(fn {_host_id, edge} -> edge.type == Contains end)

      {segment.data.name, count}
    end)
  end

  defp node_by_name(graph, name) do
    Enum.find(Graph.nodes(graph), &(&1.data.name == name))
  end

  defp order_api_policy(graph) do
    Enum.find(Graph.edges(graph), fn edge ->
      edge.type == SegmentReachability and edge.data.port_start == 8080 and
        Graph.node(graph, edge.from_id).data.name == "Public DMZ" and
        Graph.node(graph, edge.to_id).data.name == "Application"
    end)
  end

  defp external_order_gateway_policy(graph) do
    Enum.find(Graph.edges(graph), fn edge ->
      edge.type == SegmentReachability and edge.data.port_start == 443 and
        Graph.node(graph, edge.from_id).data.name == "External" and
        Graph.node(graph, edge.to_id).data.name == "Public DMZ"
    end)
  end

  defp order_processing_status(graph) do
    graph
    |> MissionImpact.pre_attack_status()
    |> Enum.find(&(&1.name == "Order processing"))
  end

  defp patch_identifier(graph, %PatchVulnerability{edge_id: edge_id}) do
    graph
    |> Graph.edge(edge_id)
    |> then(&Graph.node(graph, &1.to_id))
    |> then(& &1.data.identifier)
  end

  defp patch_identifier(_graph, _action), do: nil

  defp policy_properties(graph, edge_id) do
    edge = Graph.edge(graph, edge_id)

    {Graph.node(graph, edge.from_id).data.name, Graph.node(graph, edge.to_id).data.name,
     edge.data.port_start}
  end

  defp strategy_params(internet_entry, model \\ %{}) do
    %{
      simulation_params: %{
        monte_carlo_trials: 20,
        iterations_per_run: 5,
        initial_foothold_node_id: internet_entry.id,
        seed: 42,
        max_attempts: 1
      },
      model: model
    }
  end

  defp cvss(metrics),
    do:
      struct!(
        Cvss,
        Map.new(metrics, fn {key, value} ->
          {String.to_existing_atom(key), String.to_existing_atom(value)}
        end)
      )

  defp nvd_file!(name) do
    __DIR__
    |> Path.join("../../../../evaluation/scenarios/fixed-order-fulfilment-v1/nvd/#{name}")
    |> Path.expand()
    |> File.read!()
    |> Jason.decode!()
  end
end
