defmodule NetworkDefense.Simulation.SimulationReportTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.{Graph, Node}
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.SimulationReport
  alias NetworkDefense.Simulation.Run
  alias NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply

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
    assert {:ok,
            %FetchSimulationReportReply{
              summary: %{expected_blast_radius: 1.0},
              charts: %{convergence: [%{run: 1, mean_blast_radius: 1.0}]}
            }} =
             experiment([run("source-host")])
             |> SimulationReport.generate()
             |> FetchSimulationReportReply.from_domain()
  end

  defp experiment(runs) do
    %Experiment{
      id: "experiment",
      graph_id: "graph",
      graph: %Graph{title: "Test graph", nodes: [%Node{}, %Node{}, %Node{}]},
      iteration_count: 1,
      runs: runs
    }
  end

  defp run(foothold) do
    Run.new(initial_attacker_state: AttackerState.new(foothold))
  end
end
