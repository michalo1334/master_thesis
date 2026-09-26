defmodule NetworkDefenseWeb.ContractsGenTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.{Registry, TypespecParser}

  @dashboard_categories [
    :graph,
    :simulation,
    :optimization,
    :workflow,
    :workspace,
    :evaluation,
    :runs
  ]

  test "renders contract types from typespecs and metadata" do
    output = Registry.render_all()

    assert output =~ "export declare namespace NetworkDefense.Graph.Contracts"
    assert output =~ "export declare namespace NetworkDefense.Graph.Contracts.Data"
    assert output =~ "export declare namespace NetworkDefenseWeb.Contracts.Dashboard"
    assert output =~ "export declare namespace NetworkDefenseWeb.Contracts.Dashboard.Evaluation"
    refute output =~ "NetworkDefenseWeb.Web.Contracts"

    assert output =~ "  export type Node ="
    assert output =~ "    | HostNode"
    assert output =~ "    | ServiceNode"
    assert output =~ "    | VulnerabilityNode"
    assert output =~ "    | CredentialNode"
    assert output =~ "    | NetworkSegmentNode"
    assert output =~ "    | MissionCapabilityNode;"

    assert output =~ "type: \"Host\";"
    assert output =~ "data: NetworkDefense.Graph.Contracts.Data.HostData;"

    assert output =~ "  export type Edge ="
    assert output =~ "    | RunsEdge"
    assert output =~ "    | SegmentReachabilityEdge"
    assert output =~ "    | HasVulnerabilityEdge"
    assert output =~ "    | StoresCredentialEdge"
    assert output =~ "    | AuthenticatesToEdge"
    assert output =~ "    | ContainsEdge"
    assert output =~ "    | SupportsEdge;"

    refute output =~ "NetworkReachability"

    assert output =~ "protocol: \"tcp\" | \"udp\";"
    assert output =~ "protocol: \"tcp\" | \"udp\" | \"any\";"
    assert output =~ "version?: string | null;"
    assert output =~ "nodes: NetworkDefense.Graph.Contracts.Node[];"
    assert output =~ "graph?:"
    assert output =~ "NetworkDefense.Graph.Contracts.GraphContract | null;"
    assert output =~ "export interface RunSimulationRequest"
    assert output =~ "export declare namespace NetworkDefense.Errors"
    assert output =~ "  export type ErrorCode ="
    assert output =~ "code: NetworkDefense.Errors.ErrorCode;"
    assert output =~ "correlation_id: string;"
    assert output =~ "status: \"accepted\" | \"rejected\";"
    assert output =~ "export interface SimulationCompletedEvent"
    assert output =~ "experiment_id: string;"
    assert output =~ "export interface SimulationFailedEvent"
    assert output =~ "export interface RunOptimizationRequest"
    assert output =~ "export interface OptimizationCompletedEvent"

    assert output =~
             "export interface EvaluationAnalysisErrorEvent {\n    document_id: string;\n    error: NetworkDefenseWeb.Contracts.Dashboard.DashboardError;\n    mode: \"pilot\" | \"analyze\";"

    assert output =~ "export interface SimulationReportCapabilityStatus"
    assert output =~ "required_flow_count: number;"
    assert output =~ "missing_flow_count: number;"
    assert output =~ "supporting_host_count: number;"
    assert output =~ "min_operational_support: number;"

    assert output =~
             "capability_statuses: NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCapabilityStatus[];"

    assert output =~ "feasible: boolean;"
    assert output =~ "content?: Record<string, unknown> | null;"
    assert output =~ "content: Record<string, unknown>;"

    refute output =~ ~r/^export (interface|type) /m
  end

  test "discovers contracts for multiple categories" do
    modules = Registry.list_contract_modules(@dashboard_categories)

    assert NetworkDefense.Graph.Contracts.GraphContract in modules
    assert NetworkDefense.Simulation.Contracts.RunSimulationRequest in modules
    assert NetworkDefense.Optimization.Contracts.RunOptimizationRequest in modules
    assert NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchSimulationReportReply in modules
    assert NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.Anchor in modules
    assert NetworkDefense.Graph.Contracts.GraphContract.contract_category() == :graph

    assert NetworkDefense.Simulation.Contracts.RunSimulationRequest.contract_category() ==
             :simulation

    assert NetworkDefense.Optimization.Contracts.RunOptimizationRequest.contract_category() ==
             :optimization

    assert Registry.list_contract_modules(:operations) == []
  end

  test "filters contracts by category" do
    modules = Registry.list_contract_modules(:graph)

    assert NetworkDefense.Graph.Contracts.GraphContract in modules
    assert NetworkDefenseWeb.Contracts.Dashboard.Graph.SaveGraphPayload in modules
    refute NetworkDefense.Simulation.Contracts.RunSimulationRequest in modules
    refute NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchSimulationReportReply in modules
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
               NetworkDefense.Graph.Contracts.Data.CredentialData,
               NetworkDefense.Graph.Contracts.Data.NetworkSegmentData,
               NetworkDefense.Graph.Contracts.Data.MissionCapabilityData
             ])
  end

  test "generated file is in sync with contracts" do
    assert File.read!(Registry.output_path()) == Registry.render_all()
  end

  test "generates runtime field metadata from typespecs and enum metadata" do
    output = Registry.render_runtime_metadata()

    assert output =~
             ~s("NetworkDefense.Graph.Contracts.Data.ServiceData": {\n    fields: [\n      {\n        name: "name",\n        kind: "string",\n        nullable: false,\n      },)

    assert output =~
             ~s(      {\n        name: "cvss",\n        kind: "object",\n        nullable: false,\n        contract: "NetworkDefense.Graph.Contracts.Data.CvssData",\n      })

    assert output =~
             ~s(      {\n        name: "required_flows",\n        kind: "list",\n        nullable: false,\n        itemContract:\n          "NetworkDefense.Graph.Contracts.Data.RequiredServiceFlowData",\n      })

    assert output =~
             ~s(      {\n        name: "attack_vector",\n        kind: "enum",\n        nullable: false,\n        choices: ["network", "adjacent", "local", "physical"],\n      })

    refute output =~ "NetworkDefense.Simulation.Contracts"
    refute output =~ "NetworkDefenseWeb.Contracts.Dashboard"
    refute output =~ "required:"
    refute output =~ "minimum:"
  end

  test "generates graph data contract mappings from discriminant metadata" do
    output = Registry.render_runtime_metadata()

    assert output =~ "export const nodeDataContracts = {"
    assert output =~ ~s(Host: "NetworkDefense.Graph.Contracts.Data.HostData")
    assert output =~ "export const edgeDataContracts = {"
    assert output =~ ~s(Runs: "NetworkDefense.Graph.Contracts.Data.RunsData")
  end

  test "generated runtime metadata file is in sync with contracts" do
    assert File.read!(Registry.runtime_output_path()) == Registry.render_runtime_metadata()
  end

  test "uses a global generated file" do
    assert Registry.output_path() ==
             Path.join(File.cwd!(), "assets/svelte/contracts.generated.ts")
  end

  test "generates type-only import modules per domain" do
    modules = Map.new(Registry.render_import_modules())

    for rel_path <- [
          "errors.ts",
          "graph.ts",
          "graph/data.ts",
          "optimization.ts",
          "simulation.ts",
          "dashboard.ts",
          "dashboard/evaluation.ts",
          "dashboard/graph.ts",
          "dashboard/graph/topology_projection.ts",
          "dashboard/optimization.ts",
          "dashboard/runs.ts",
          "dashboard/simulation.ts",
          "dashboard/workspace.ts"
        ] do
      assert Map.has_key?(modules, rel_path), "missing import module #{rel_path}"
    end

    evaluation = modules["dashboard/evaluation.ts"]
    assert evaluation =~ ~s(import type * as __Contracts from "../../contracts.generated";)

    assert evaluation =~
             ~s(export type DescribeManifestPayload = __Contracts.NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeManifestPayload;)

    graph_data = modules["graph/data.ts"]
    assert graph_data =~ ~s(import type * as __Contracts from "../../contracts.generated";)

    assert graph_data =~
             ~s(export type HostData = __Contracts.NetworkDefense.Graph.Contracts.Data.HostData;)

    assert graph_data =~
             ~s(export { contractMetadata } from "../../contracts.generated.runtime";)

    errors = modules["errors.ts"]
    assert errors =~ ~s(import type * as __Contracts from "../contracts.generated";)
    assert errors =~ ~s(export type ErrorCode = __Contracts.NetworkDefense.Errors.ErrorCode;)

    graph = modules["graph.ts"]
    assert graph =~ ~s(export type Node = __Contracts.NetworkDefense.Graph.Contracts.Node;)

    assert graph =~
             ~s(export type HostNode = __Contracts.NetworkDefense.Graph.Contracts.HostNode;)

    assert graph =~
             ~s(export { edgeDataContracts, nodeDataContracts } from "../contracts.generated.runtime";)

    dashboard = modules["dashboard.ts"]
    assert dashboard =~ ~s(import type * as __Contracts from "../contracts.generated";)

    topology_projection = modules["dashboard/graph/topology_projection.ts"]

    for child <- ~w(Anchor Attachment FlowGroup Host Issue PolicyGroup Segment Service) do
      assert topology_projection =~
               "export type #{child} = __Contracts.NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.#{child};"
    end

    refute graph =~ "TopologyProjectionHost"

    assert Map.keys(modules) |> Enum.sort() == [
             "dashboard.ts",
             "dashboard/evaluation.ts",
             "dashboard/graph.ts",
             "dashboard/graph/topology_projection.ts",
             "dashboard/optimization.ts",
             "dashboard/runs.ts",
             "dashboard/simulation.ts",
             "dashboard/workspace.ts",
             "errors.ts",
             "graph.ts",
             "graph/data.ts",
             "optimization.ts",
             "simulation.ts"
           ]
  end

  test "generated import modules are in sync with contracts" do
    for {rel_path, content} <- Registry.render_import_modules() do
      full = Path.join(Registry.import_modules_dir(), rel_path)
      assert File.read!(full) == content, "import module out of sync: #{rel_path}"
    end
  end
end
