defmodule NetworkDefense.Optimization.Optimizer do
  @moduledoc false

  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Graph.Graph

  require OpenTelemetry.Tracer, as: Tracer

  @spec apply(Graph, Strategy.t(), Budget.t(), keyword()) :: Graph
  def apply(graph, _strategy, _budget, _opts) do
    Tracer.with_span "optimizer.apply" do
      {elapsed_us, optimized_graph} = :timer.tc(fn -> graph end)

      :telemetry.execute(
        [:network_defense, :optimizer, :run],
        %{duration: System.convert_time_unit(elapsed_us, :microsecond, :native)},
        %{}
      )

      optimized_graph
    end
  end
end
