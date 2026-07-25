defprotocol NetworkDefense.DefenseActions.DefenseAction do
  @moduledoc """
  Represents an application of a defense action during optimization phase.

  Each action has fixed budget cost.
  """
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Node

  @type target_type :: Node | Edge
  @type target_id :: Ecto.UUID

  @type target :: {target_type(), target_id()}

  @doc """
  Get the target specification - type and id.
  Used for generic enumeration over the actions.
  """
  @spec target(t()) :: target()
  def target(action)

  @spec cost(t()) :: non_neg_integer()
  def cost(action)

  @doc """
  Get the eligible types of edges or nodes that this action can apply to/operates on
  """
  @spec eligible_types(t()) :: [module()]
  def eligible_types(action)

  @spec apply(t(), Graph.t()) :: Graph.t()
  def apply(action, graph)
end
