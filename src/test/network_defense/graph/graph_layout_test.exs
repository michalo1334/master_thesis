defmodule NetworkDefense.Graph.GraphLayoutTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.GraphLayout
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Vec2

  test "none returns the graph unchanged" do
    graph = Graph.new("unchanged")

    assert GraphLayout.lay_out(:none, graph, []) == graph
  end

  test "returns an empty graph" do
    graph = Graph.new("empty")

    assert GraphLayout.lay_out(:force_directed, graph, iteration: 10) == graph
  end

  test "preserves stored positions when no iterations are requested" do
    {graph, node} = add_node(Graph.new("single"), 125, 250)

    result = GraphLayout.lay_out(:force_directed, graph, iteration: 0)

    assert Node.position(Graph.node(result, node.id)) == {125, 250}
  end

  test "pulls connected nodes toward their preferred edge length" do
    {graph, source} = add_node(Graph.new("connected"), 0, 0, %{"label" => "source"})
    {graph, target} = add_node(graph, 300, 0)
    {graph, edge} = add_edge(graph, source, target)

    result =
      GraphLayout.lay_out(:force_directed, graph,
        iteration: 1,
        repulsion_strength: 0.0,
        spring_strength: 1.0,
        preferred_edge_length: 100.0,
        damping: 1.0,
        temperature: 20.0
      )

    result_source = Graph.node(result, source.id)
    result_target = Graph.node(result, target.id)

    assert distance(result_source, result_target) < distance(source, target)
    assert result_source.view_data["label"] == "source"
    assert Enum.map(Graph.edges(result), & &1.id) == [edge.id]
  end

  test "pushes disconnected nodes apart" do
    {graph, left} = add_node(Graph.new("disconnected"), 0, 0)
    {graph, right} = add_node(graph, 10, 0)

    result =
      GraphLayout.lay_out(:force_directed, graph,
        iteration: 1,
        repulsion_strength: 100.0,
        spring_strength: 0.0,
        damping: 1.0,
        temperature: 20.0
      )

    assert distance(Graph.node(result, left.id), Graph.node(result, right.id)) >
             distance(left, right)
  end

  test "separates coincident nodes without invalid coordinates" do
    {graph, left} = add_node(Graph.new("coincident"), 10, 10)
    {graph, right} = add_node(graph, 10, 10)

    result =
      GraphLayout.lay_out(:force_directed, graph,
        iteration: 1,
        repulsion_strength: 1.0,
        spring_strength: 0.0
      )

    left_position = Node.position(Graph.node(result, left.id))
    right_position = Node.position(Graph.node(result, right.id))

    assert left_position != right_position
    assert Enum.all?(Tuple.to_list(left_position) ++ Tuple.to_list(right_position), &is_number/1)
  end

  test "limits each iteration's displacement to the current temperature" do
    {graph, source} = add_node(Graph.new("limited"), 0, 0)
    {graph, target} = add_node(graph, 1_000, 0)
    {graph, _edge} = add_edge(graph, source, target)

    result =
      GraphLayout.lay_out(:force_directed, graph,
        iteration: 1,
        repulsion_strength: 0.0,
        spring_strength: 1.0,
        preferred_edge_length: 100.0,
        damping: 1.0,
        temperature: 5.0
      )

    source_displacement =
      result
      |> Graph.node(source.id)
      |> Node.position()
      |> Vec2.sub(Node.position(source))
      |> Vec2.length()

    assert_in_delta source_displacement, 5.0, 1.0e-10
  end

  test "cools the maximum displacement once per iteration" do
    {graph, source} = add_node(Graph.new("cooling"), 0, 0)
    {graph, target} = add_node(graph, 300, 0)
    {graph, _edge} = add_edge(graph, source, target)

    result =
      GraphLayout.lay_out(:force_directed, graph,
        iteration: 2,
        repulsion_strength: 0.0,
        spring_strength: 1.0,
        preferred_edge_length: 100.0,
        damping: 1.0,
        temperature: 10.0,
        cooling_rate: 0.5
      )

    assert Node.position(Graph.node(result, source.id)) == {15.0, 0.0}
    assert Node.position(Graph.node(result, target.id)) == {285.0, 0.0}
  end

  test "rejects a non-integer iteration count" do
    assert_raise ArgumentError, ":iteration must be an integer, got: 1.5", fn ->
      GraphLayout.lay_out(:force_directed, Graph.new("invalid"), iteration: 1.5)
    end
  end

  defp add_node(graph, x_pos, y_pos, extra_view_data \\ %{}) do
    node =
      Node.new(graph.id, %{
        type: "host",
        data: %{},
        view_data: Map.merge(extra_view_data, %{"x_pos" => x_pos, "y_pos" => y_pos})
      })

    {Graph.add_node(graph, node), node}
  end

  defp add_edge(graph, from, to) do
    edge = Edge.new(graph.id, from.id, to.id, %{type: "connection", data: %{}})
    {Graph.add_edge(graph, edge), edge}
  end

  defp distance(left, right) do
    left
    |> Node.position()
    |> Vec2.sub(Node.position(right))
    |> Vec2.length()
  end
end
