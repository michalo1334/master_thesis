defmodule NetworkDefense.Simulation.ReportTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Report
  alias NetworkDefense.Simulation.Run

  test "generates a convergence chart for completed simulations" do
    report = Report.generate(experiment([run("source-host")]))

    assert [%{id: "mean-convergence", option: %{series: [%{data: [1.0]}]}}] =
             report.charts.convergence
  end

  test "generates an empty convergence chart when no simulations were persisted" do
    report = Report.generate(experiment([]))

    assert [
             %{
               takeaway: "No completed simulation runs are available.",
               option: %{series: [%{data: []}]}
             }
           ] =
             report.charts.convergence
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
