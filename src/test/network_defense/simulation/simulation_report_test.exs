defmodule NetworkDefense.Simulation.SimulationReportTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Actions.AttemptedAction
  alias NetworkDefense.Actions.ExploitVulnerability
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Nodes.{Host, Service}
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.IterationStep
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Run
  alias NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply

  import NetworkDefense.GraphFixtures

  test "generates grouped raw report data for completed simulations" do
    report = SimulationReport.generate(experiment([run("source-host")]))

    assert %{expected_blast_radius: 1.0, median_blast_radius: 1, host_count: 3} = report.summary

    assert %SimulationReport.Charts{
             histogram: [%{lower_bound: 1, upper_bound: 1, count: 1}],
             cdf: [%{compromised_hosts: 1, cumulative_probability: 1.0}],
             convergence: [%{run: 1, mean_blast_radius: 1.0}],
             action_success: []
           } = report.charts
  end

  test "returns empty series when no simulations were persisted" do
    report = SimulationReport.generate(experiment([]))

    assert %SimulationReport.Charts{
             cdf: [],
             convergence: [],
             action_success: []
           } = report.charts
  end

  test "maps a typed report to the web contract" do
    graph = %{Graph.new("Test graph") | revision_id: Ecto.UUID.generate()}

    assert {:ok,
            %FetchSimulationReportReply{
              summary: %{expected_blast_radius: 1.0},
              charts: %{convergence: [%{run: 1, mean_blast_radius: 1.0}]}
            }} =
             experiment([run("source-host")], graph)
             |> SimulationReport.generate()
             |> FetchSimulationReportReply.from_domain(graph)
  end

  test "aggregates host compromise and successful edge traversal by run" do
    source = node("source-host", Host, %{"name" => "source"})
    service = node("service", Service, %{"name" => "ssh", "port" => 22, "protocol" => "tcp"})

    graph =
      graph([source, service], [edge("reach", source, service, NetworkReachability)])

    report =
      [run("source-host", ["reach"]), run("source-host")]
      |> experiment(graph)
      |> SimulationReport.generate()

    assert report.charts.host_compromise == [
             %{host_id: "source-host", compromise_probability: 1.0}
           ]

    assert report.charts.edge_traversal == [
             %{edge_id: "reach", traversal_probability: 0.5}
           ]
  end

  defp experiment(
         runs,
         graph \\ %Graph{
           id: "graph",
           revision_id: "revision",
           title: "Test graph",
           nodes: [%{}, %{}, %{}]
         }
       ) do
    %Experiment{
      id: "experiment",
      graph_revision_id: graph.revision_id,
      graph: graph,
      iteration_count: 1,
      runs: runs
    }
  end

  defp run(foothold, supporting_edge_ids \\ nil) do
    state = AttackerState.new(foothold)

    Run.new(
      seed: 0,
      initial_attacker_state: state,
      iterations:
        if supporting_edge_ids do
          action = %ExploitVulnerability{
            source_host_id: foothold,
            supporting_edge_ids: supporting_edge_ids
          }

          [
            IterationStep.new(
              index: 1,
              success?: true,
              attempted_action: AttemptedAction.new(action),
              attacker_state: state
            )
          ]
        else
          []
        end
    )
  end
end
