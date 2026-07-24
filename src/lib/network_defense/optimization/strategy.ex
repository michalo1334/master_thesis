defprotocol NetworkDefense.Optimization.Strategy do
  @moduledoc """
  Protocol for defense optimization strategies. Optimization strategy is an algorithm whose intent is to reduce potential attack vectors by applying security actions such as patching vulnerabilities or segment network.

  The base function is apply() - accepts initial context graph containing network topology as well as vulnerabilirty info and return a new graph that is result of applying the strategy.
  """

  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.AttackerState.Graph
  @spec name(t()) :: String.t()
  def name(strategy)

  @spec apply(t(), Graph) :: Graph
  def apply(strategy, graph)
end
