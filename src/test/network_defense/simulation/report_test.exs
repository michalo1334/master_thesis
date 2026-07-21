defmodule NetworkDefense.Simulation.ReportTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Simulation.MultiState
  alias NetworkDefense.Simulation.Report
  alias NetworkDefense.Simulation.State

  test "generates a convergence chart for completed simulations" do
    report = Report.generate(multi_state([simulation("source-host")]))

    assert [%{id: "mean-convergence", option: %{series: [%{data: [1.0]}]}}] =
             report.charts.convergence
  end

  test "generates an empty convergence chart when no simulations were persisted" do
    report = Report.generate(multi_state([]))

    assert [
             %{
               takeaway: "No completed simulation runs are available.",
               option: %{series: [%{data: []}]}
             }
           ] =
             report.charts.convergence
  end

  defp multi_state(simulations) do
    %MultiState{
      id: "multi-state",
      graph_id: "graph",
      iteration_count: 1,
      simulations: simulations
    }
  end

  defp simulation(foothold) do
    State.new(initial_attacker_state: AttackerState.new(foothold))
  end
end
