defmodule NetworkDefenseWeb.ContractsGenTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.Registry

  test "renders contract types from typespecs and metadata" do
    output = Registry.render_all(:dashboard)

    assert output =~ "export type Node = HostNode | ServiceNode | VulnerabilityNode;"
    assert output =~ "type: \"Host\";"
    assert output =~ "data: HostData;"

    assert output =~
             "export type Edge = RunsEdge | NetworkReachabilityEdge | HasVulnerabilityEdge;"

    assert output =~ "protocol: \"tcp\" | \"udp\";"
    assert output =~ "version?: string | null;"
    assert output =~ "nodes: Node[];"
    assert output =~ "graph?: GraphContract | null;"
    assert output =~ "export interface RunSimulationRequest"
    assert output =~ "correlation_id: string;"
    assert output =~ "status: \"accepted\" | \"rejected\";"
    assert output =~ "export interface SimulationCompletedEvent"
    assert output =~ "simulation_id: string;"
    assert output =~ "export interface SimulationFailedEvent"
    assert output =~ "export interface OptimizeDefensePayload"
  end

  test "discovers core and web contracts by category" do
    modules = Registry.list_contract_modules(:dashboard)

    assert NetworkDefense.Graph.Contracts.GraphContract in modules
    assert NetworkDefense.Simulation.Contracts.RunSimulationRequest in modules
    assert NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply in modules
    assert NetworkDefense.Graph.Contracts.GraphContract.contract_category() == :dashboard
    assert Registry.list_contract_modules(:operations) == []
  end

  test "generated file is in sync with contracts" do
    assert File.read!(Registry.output_path(:dashboard)) == Registry.render_all(:dashboard)
  end

  test "derives the generated file path from the category" do
    assert Registry.output_path(:operations) ==
             Path.join(File.cwd!(), "assets/svelte/operations/contracts.generated.ts")
  end

  test "rejects unsafe category paths" do
    assert_raise ArgumentError, fn -> Registry.output_path("../operations") end
  end
end
