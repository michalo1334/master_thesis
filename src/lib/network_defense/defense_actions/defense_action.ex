defprotocol NetworkDefense.DefenseActions.DefenseAction do
  @moduledoc """
  Represents an application of a defense action during optimization phase.

  Each action has fixed budget cost.
  """

  def cost(action)

  def apply(action, graph)
end
