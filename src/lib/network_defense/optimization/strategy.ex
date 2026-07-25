defprotocol NetworkDefense.Optimization.Strategy do
  @moduledoc """
  Protocol for defense optimization strategies. Optimization strategy is an algorithm whose intent is to reduce potential attack vectors by applying security actions such as patching vulnerabilities or segment network.

  Each strategy works according to fixed cost budget. After exhausting budget, resulting graph can be further evaluated for comparision with respect to baseline one.

  Strategies return only ranked candidate defense actions, which are then picked up by the optimizer to evaluate. This keeps budget tracking exlusive to the optimizer
  """

  @type t :: __MODULE__

  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.Actions.Action
  alias NetworkDefense.Graph.Graph

  @spec name(t()) :: String.t()
  def name(strategy)

  @spec rank(t(), Graph.t(), Budget.t()) :: list(Action.t())
  def rank(strategy, graph, budget)
end
