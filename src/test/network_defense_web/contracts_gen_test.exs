defmodule NetworkDefenseWeb.ContractsGenTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.Registry

  test "renders contract types from typespecs and metadata" do
    output = Registry.render_all()

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
end
