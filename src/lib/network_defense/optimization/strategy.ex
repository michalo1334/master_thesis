defprotocol NetworkDefense.Optimization.Strategy do
  @moduledoc """
  Protocol for defense optimization strategies. Optimization strategy is an algorithm whose intent is to reduce potential attack vectors by applying security actions such as patching vulnerabilities or segment network.

  Each strategy works according to fixed cost budget. After exhausting budget, resulting graph can be further evaluated for comparision with respect to baseline one.

  Strategies return only ranked candidate defense actions, which are then picked up by the optimizer to evaluate. This keeps budget tracking exlusive to the optimizer
  """

  @type t :: struct()

  alias NetworkDefense.Optimization.Budget
  alias NetworkDefense.DefenseActions.DefenseAction
  alias NetworkDefense.Graph.Graph

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
