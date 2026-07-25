defmodule NetworkDefense.Optimization.Optimizer do
  @moduledoc false

  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Optimization.Strategy
  alias NetworkDefense.Graph.Graph

  @spec apply(Graph, Strategy.t(), Budget.t(), keyword()) :: Graph
  def apply(graph, _strategy, _budget, _opts), do: graph
end
