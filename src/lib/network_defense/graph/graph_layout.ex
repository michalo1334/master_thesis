defmodule NetworkDefense.Graph.GraphLayout do
  @moduledoc """
  Various layout strategies for graph.
  """
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Vec2

  @doc """
  Layout graph nodes according to selected strategy.

  Currently available:

  - do nothing
  - force directed
  """
  def lay_out(:none, %Graph{} = graph, _opts), do: graph

  def lay_out(:force_directed, %Graph{} = graph, opts) do
    # initial state
    initial_state =
      %{
        nodes:
          graph.nodes |> Enum.map(&%{&1 | position: random_position(), velocity: zero_vector()}),
        edges: graph.edges,
        repulsion_strength: Keyword.get(opts, :repulsion_strength, 1.0),
        spring_strength: Keyword.get(opts, :spring_strength, 1.0),
        preferred_edge_length: Keyword.get(opts, :preferred_edge_length, 100),
        damping: Keyword.get(opts, :damping, 1.0),
        temperature: Keyword.get(opts, :temperature, 20.0),
        cooling_rate: Keyword.get(opts, :cooling_rate, 0.95),
        iteration: Keyword.get(opts, :iteration, 1000)
      }

    _final_state =
      Enum.reduce(1..initial_state.iteration, initial_state, fn index, each ->
        force_directed_simulation_step(%{each | iteration: index})
      end)

    # Conver to Node / Graph{}
  end

  def lay_out(_strategy, %Graph{} = _graph, _opts), do: raise("invalid strategy")

  defp force_directed_simulation_step(%{nodes: nodes, edges: edges} = state) do
    node_repulsive_forces =
      nodes
      |> all_node_pairs()
      |> Enum.map(fn each -> repulsive_force(each, state) end)
      |> Enum.flat_map(fn {left, right} -> [left, right] end)
      |> Enum.group_by(& &1.id)
      |> Map.new(fn {node, forces} -> {node.id, Enum.sum(forces)} end)

    node_attractive_forces =
      edges
      |> Enum.map(fn each -> attractive_force(each, state) end)
      |> Enum.flat_map(fn {left, right} -> [left, right] end)
      |> Enum.group_by(& &1.id)
      |> Map.new(fn {node, forces} -> {node.id, Enum.sum(forces)} end)

    # {node -> forces}
    forces_by_node =
      nodes
      |> Enum.map(fn each ->
        {each.id,
         Map.get(node_repulsive_forces, each.id) + Map.get(node_attractive_forces, each.id)}
      end)

    # acceleration = force

    updated_nodes =
      nodes
      |> Enum.map(fn %{id: id, position: position, velocity: velocity} = each ->
        # velocity + acceleration
        next_velocity = Vec2.add(velocity, Map.get(forces_by_node, id)) |> Vec2.mul(state.damping)

        limited_velocity = min(Vec2.length(next_velocity), state.temperature)

        %{each | position: Vec2.add(position, limited_velocity), velocity: limited_velocity}
      end)

    %{
      state
      | nodes: updated_nodes,
        temperature: state.temperature * Float.pow(state.cooling_rate, state.iteration)
    }
  end

  defp all_node_pairs(state) do
    for left <- state.nodes, right <- state.nodes, do: {left, right}
  end

  defp repulsive_force(%{left: left, right: right} = _node_pair, state) do
    delta = Vec2.sub(left, right)
    direction = Vec2.normalize(delta)

    magnitude = Vec2.force_magnitude(delta, state.repulsion_strength)

    {
      Vec2.mul(direction, magnitude),
      Vec2.mul(Vec2.mul(-1, direction), magnitude)
    }
  end

  defp attractive_force(edge, state) do
    delta = Vec2.sub(Node.position(edge.from), Node.position(edge.to))
    distance = Vec2.length(delta)
    direction = Vec2.normalize(delta)

    stretch = distance - state.preferred_edge_length

    magnitude = state.spring_strength * stretch

    {
      Vec2.mul(direction, magnitude),
      Vec2.mul(Vec2.mul(-1, direction), magnitude)
    }
  end

  defp random_position(), do: {:rand.uniform(1000), :rand.uniform(1000)}

  defp zero_vector(), do: {0.0, 0.0}
end
