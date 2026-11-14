defmodule NetworkDefense.Graph.Drafts do
  @moduledoc false

  alias NetworkDefense.Graph.Contracts.{Edge, Node}
  alias NetworkDefense.Graph.SemanticConnectivity
  alias NetworkDefense.Nodes.Registry, as: NodeRegistry
  alias NetworkDefense.Relationships.Registry, as: RelationshipRegistry

  def node(type, %{x_pos: x_pos, y_pos: y_pos})
      when is_binary(type) and is_number(x_pos) and is_number(y_pos) do
    with module when not is_nil(module) <- NodeRegistry.module_for_contract(type),
         {:ok, node} <-
           Node.validate(%{
             id: Ecto.UUID.generate(),
             type: type,
             data: module.default_data(),
             view_data: %{x_pos: x_pos, y_pos: y_pos}
           }) do
      {:ok, Node.to_wire(node)}
    else
      _ -> :error
    end
  end

  def node(_type, _position), do: :error

  def edge(relationship_type, %{id: from_id, type: from_type}, %{id: to_id, type: to_type})
      when is_binary(relationship_type) and is_binary(from_id) and is_binary(to_id) do
    with relationship when not is_nil(relationship) <-
           RelationshipRegistry.module_for_contract(relationship_type),
         from when not is_nil(from) <- NodeRegistry.module_for_contract(from_type),
         to when not is_nil(to) <- NodeRegistry.module_for_contract(to_type),
         true <- SemanticConnectivity.valid?(relationship, from, to),
         {:ok, edge} <-
           Edge.validate(%{
             id: Ecto.UUID.generate(),
             from_id: from_id,
             to_id: to_id,
             type: relationship_type,
             data: relationship.default_data()
           }) do
      {:ok, Edge.to_wire(edge)}
    else
      _ -> :error
    end
  end

  def edge(_relationship_type, _from, _to), do: :error
end
