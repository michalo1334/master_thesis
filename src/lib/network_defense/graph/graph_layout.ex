defmodule NetworkDefense.Graph.GraphLayout do
  @moduledoc """
  Various layout strategies for graph.
  """
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Vec2

  @doc """
  Layout graph nodes according to selected strategy.

  Currently available:

  - do nothing
  - force directed
  """
  def lay_out(:none, %Graph{} = graph, _opts), do: graph

  def lay_out(:force_directed, %Graph{} = graph, opts) do
    state = %{
      nodes:
        Enum.map(Graph.nodes(graph), fn node ->
          %{id: node.id, position: Node.position(node), velocity: zero_vector()}
        end),
      edges: Graph.edges(graph),
      repulsion_strength: Keyword.get(opts, :repulsion_strength, 1.0),
      spring_strength: Keyword.get(opts, :spring_strength, 1.0),
      preferred_edge_length: Keyword.get(opts, :preferred_edge_length, 100),
      damping: Keyword.get(opts, :damping, 1.0),
      temperature: Keyword.get(opts, :temperature, 20.0),
      cooling_rate: Keyword.get(opts, :cooling_rate, 0.95)
    }

    final_state = run_simulation(state, Keyword.get(opts, :iteration, 1000))
    positions_by_id = Map.new(final_state.nodes, &{&1.id, &1.position})

    nodes =
      Enum.map(Graph.nodes(graph), fn node ->
        {x_pos, y_pos} = Map.fetch!(positions_by_id, node.id)

        %{
          node
          | view_data:
              node.view_data
              |> Map.put("x_pos", x_pos)
              |> Map.put("y_pos", y_pos)
        }
      end)

    %{graph | nodes: nodes}
  end

  def lay_out(_strategy, %Graph{} = _graph, _opts), do: raise("invalid strategy")

  defp run_simulation(state, iterations) when is_integer(iterations) and iterations > 0 do
    Enum.reduce(1..iterations, state, fn _iteration, current_state ->
      force_directed_simulation_step(current_state)
    end)
  end

  defp run_simulation(state, iterations) when is_integer(iterations) and iterations <= 0,
    do: state

  defp run_simulation(_state, iterations) do
    raise ArgumentError, ":iteration must be an integer, got: #{inspect(iterations)}"
  end

  defp force_directed_simulation_step(%{nodes: nodes, edges: edges} = state) do
    nodes_by_id = Map.new(nodes, &{&1.id, &1})
    zero_forces = Map.new(nodes, &{&1.id, zero_vector()})

    forces_by_node =
      nodes
      |> add_repulsive_forces(zero_forces, state)
      |> then(fn forces ->
        Enum.reduce(edges, forces, fn edge, edge_forces ->
          from = Map.fetch!(nodes_by_id, edge.from_id)
          to = Map.fetch!(nodes_by_id, edge.to_id)
          {from_force, to_force} = attractive_force(from, to, state)

          edge_forces
          |> add_force(from.id, from_force)
          |> add_force(to.id, to_force)
        end)
      end)

    updated_nodes =
      Enum.map(nodes, fn %{id: id, position: position, velocity: velocity} = node ->
        next_velocity =
          velocity
          |> Vec2.add(Map.fetch!(forces_by_node, id))
          |> Vec2.mul(state.damping)
          |> limit(state.temperature)

        %{node | position: Vec2.add(position, next_velocity), velocity: next_velocity}
      end)

    %{state | nodes: updated_nodes, temperature: state.temperature * state.cooling_rate}
  end

  defp add_repulsive_forces([], forces, _state), do: forces

  defp add_repulsive_forces([left | rest], forces, state) do
    forces =
      Enum.reduce(rest, forces, fn right, current_forces ->
        {left_force, right_force} = repulsive_force(left, right, state)

        current_forces
        |> add_force(left.id, left_force)
        |> add_force(right.id, right_force)
      end)

    add_repulsive_forces(rest, forces, state)
  end

  defp repulsive_force(left, right, state) do
    delta = Vec2.sub(left.position, right.position)
    distance = Vec2.length(delta)
    direction = direction(delta)
    magnitude = state.repulsion_strength / max(distance * distance, 1.0)
    force = Vec2.mul(direction, magnitude)

    {force, Vec2.mul(force, -1)}
  end

  defp attractive_force(from, to, state) do
    delta = Vec2.sub(to.position, from.position)
    distance = Vec2.length(delta)
    direction = direction(delta)
    stretch = distance - state.preferred_edge_length
    force = Vec2.mul(direction, state.spring_strength * stretch)

    {force, Vec2.mul(force, -1)}
  end

  defp add_force(forces, node_id, force) do
    Map.update!(forces, node_id, &Vec2.add(&1, force))
  end

  defp direction(vector) do
    length = Vec2.length(vector)

    if length <= 1.0e-12 do
      {1.0, 0.0}
    else
      Vec2.mul(vector, 1.0 / length)
    end
  end

  defp limit(_vector, max_length) when max_length <= 0, do: zero_vector()

  defp limit(vector, max_length) do
    length = Vec2.length(vector)

    if length > max_length do
      Vec2.mul(vector, max_length / length)
    else
      vector
    end
  end

  defp zero_vector, do: {0.0, 0.0}
end
