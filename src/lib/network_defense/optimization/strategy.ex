defprotocol NetworkDefense.Optimization.Strategy do
  @moduledoc """
  Protocol for defense optimization strategies. A strategy reduces potential attack vectors. It can patch vulnerabilities or segment a network.

  Each strategy uses a fixed-cost budget. After the strategy exhausts the budget, callers can compare the resulting graph with the baseline graph.

  Strategies return ranked candidate defense actions. The optimizer scores these actions and tracks the budget.
  """

  @type t :: struct()

  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.Budget

  @spec name(t()) :: String.t()
  def name(strategy)

  @doc """
  Whether `rank/4` returns a jointly selected plan (all actions to apply,
  in order) instead of a ranked candidate list the optimizer picks from
  one action at a time.
  """
  @spec plan?(t()) :: boolean()
  def plan?(strategy)

  @doc """
  The rank function
  """
  @spec rank(t(), [module()], Graph.t(), Budget.t()) :: [DefenseAction.t()]
  def rank(strategy, action_types, graph, budget)
end
