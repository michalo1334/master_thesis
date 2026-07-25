defmodule NetworkDefenseWeb.ContractsGenTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.{Registry, TypespecParser}

  @dashboard_categories [:graph, :simulation, :optimization]

  test "renders contract types from typespecs and metadata" do
    output = Registry.render_all()

    assert output =~
             "export type Node = HostNode | ServiceNode | VulnerabilityNode | CredentialNode;"

    assert output =~ "type: \"Host\";"
    assert output =~ "data: HostData;"

    assert output =~
             """
             export type Edge =
               | RunsEdge
               | NetworkReachabilityEdge
               | HasVulnerabilityEdge
               | StoresCredentialEdge
               | AuthenticatesToEdge;
             """

    assert output =~ "protocol: \"tcp\" | \"udp\";"
    assert output =~ "protocol: \"tcp\" | \"udp\" | \"any\";"
    assert output =~ "version?: string | null;"
    assert output =~ "nodes: Node[];"
    assert output =~ "graph?: GraphContract | null;"
    assert output =~ "export interface RunSimulationRequest"
    assert output =~ "correlation_id: string;"
    assert output =~ "status: \"accepted\" | \"rejected\";"
    assert output =~ "export interface SimulationCompletedEvent"
    assert output =~ "experiment_id: string;"
    assert output =~ "export interface SimulationFailedEvent"
    assert output =~ "export interface OptimizeDefensePayload"
  end

  test "discovers contracts for multiple categories" do
    modules = Registry.list_contract_modules(@dashboard_categories)

    assert NetworkDefense.Graph.Contracts.GraphContract in modules
    assert NetworkDefense.Simulation.Contracts.RunSimulationRequest in modules
    assert NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply in modules
    assert NetworkDefense.Graph.Contracts.GraphContract.contract_category() == :graph

    assert NetworkDefense.Simulation.Contracts.RunSimulationRequest.contract_category() ==
             :simulation

    assert NetworkDefenseWeb.Web.Contracts.OptimizeDefensePayload.contract_category() ==
             :optimization

    assert Registry.list_contract_modules(:operations) == []
  end

  test "filters contracts by category" do
    modules = Registry.list_contract_modules(:graph)

    assert NetworkDefense.Graph.Contracts.GraphContract in modules
    assert NetworkDefenseWeb.Web.Contracts.SaveGraphPayload in modules
    refute NetworkDefense.Simulation.Contracts.RunSimulationRequest in modules
    refute NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply in modules
  end

  test "selects all contract categories" do
    assert Registry.list_contract_modules(:all) ==
             Registry.list_contract_modules(@dashboard_categories)
  end

  test "finds contract references in list and union types" do
    {:nodes, nodes_type} =
      NetworkDefense.Graph.Contracts.GraphContract
      |> TypespecParser.parse()
      |> List.keyfind(:nodes, 0)

    assert TypespecParser.referenced_modules(nodes_type) == [NetworkDefense.Graph.Contracts.Node]

    {:data, data_type} =
      NetworkDefense.Graph.Contracts.Node
      |> TypespecParser.parse()
      |> List.keyfind(:data, 0)

    assert MapSet.new(TypespecParser.referenced_modules(data_type)) ==
             MapSet.new([
               NetworkDefense.Graph.Contracts.Data.HostData,
               NetworkDefense.Graph.Contracts.Data.ServiceData,
               NetworkDefense.Graph.Contracts.Data.VulnerabilityData,
               NetworkDefense.Graph.Contracts.Data.CredentialData
             ])
  end

  test "generated file is in sync with contracts" do
    assert File.read!(Registry.output_path()) == Registry.render_all()
  end

  test "uses a global generated file" do
    assert Registry.output_path() ==
             Path.join(File.cwd!(), "assets/svelte/contracts.generated.ts")
  end
end
