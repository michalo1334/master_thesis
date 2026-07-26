defmodule NetworkDefense.Simulation.ReportTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Report
  alias NetworkDefense.Simulation.Run
  alias NetworkDefenseWeb.Web.Contracts.FetchSimulationReportReply

  test "generates a convergence chart for completed simulations" do
    report = Report.generate(experiment([run("source-host")]))

    assert %Report.Charts{
             convergence: [
               %Report.Chart{id: "mean-convergence", option: %{series: [%{data: [1.0]}]}}
             ]
           } = report.charts
  end

  test "generates an empty convergence chart when no simulations were persisted" do
    report = Report.generate(experiment([]))

    assert %Report.Charts{
             convergence: [
               %Report.Chart{
                 takeaway: "No completed simulation runs are available.",
                 option: %{series: [%{data: []}]}
               }
             ]
           } = report.charts
  end

  test "maps a typed report to the web contract" do
    assert {:ok, %FetchSimulationReportReply{charts: %{convergence: [%{id: "mean-convergence"}]}}} =
             experiment([run("source-host")])
             |> Report.generate()
             |> FetchSimulationReportReply.from_domain()
  end

  defp experiment(runs) do
    %Experiment{
      id: "experiment",
      graph_id: "graph",
      iteration_count: 1,
      runs: runs
    }
  end

  defp run(foothold) do
    Run.new(initial_attacker_state: AttackerState.new(foothold))
  end
end
