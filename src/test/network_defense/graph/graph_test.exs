defmodule NetworkDefense.Graph.GraphTest do
  use NetworkDefense.DataCase, async: true

  import Ecto.Query

  alias NetworkDefense.Graph.{Edge, Graph, GraphRevision, Graphs, Node}
  alias NetworkDefense.Nodes.{Host, Service}
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.{Experiment, IterationStep, Run}

  test "creates a graph with an immutable root revision" do
    assert {:ok, saved} = Graphs.insert(graph("Topology"))

    assert %{
             revision_number: 1,
             revision_kind: :initial,
             parent_revision_id: nil,
             title: "Topology"
           } = saved

    assert [_host, _service] = Graph.nodes(saved)
    assert [_edge] = Graph.edges(saved)
  end

  test "each save appends an edit revision without changing earlier snapshots" do
    assert {:ok, original} = Graphs.insert(graph("Topology"))
    [host, service] = Graph.nodes(original)
    [edge] = Graph.edges(original)

    attrs = %{
      "title" => "Renamed topology",
      "revision_id" => original.revision_id,
      "nodes" => [node_attrs(host), node_attrs(service)],
      "edges" => [edge_attrs(edge)]
    }

    assert {:ok, %{graph: saved}} = Graphs.replace(original.id, attrs)
    assert saved.revision_number == 2
    assert saved.revision_id != original.revision_id
    assert saved.parent_revision_id == original.revision_id
    assert Enum.map(Graph.nodes(saved), & &1.id) == Enum.map(Graph.nodes(original), & &1.id)
    assert Enum.map(Graph.edges(saved), & &1.id) == Enum.map(Graph.edges(original), & &1.id)
    assert %{title: "Topology"} = Graphs.load_revision!(original.revision_id)

    assert {:ok, %{parent_revision_id: parent_revision_id}} =
             NetworkDefense.Graph.Contracts.GraphContract.from_domain(saved)

    assert parent_revision_id == original.revision_id
  end

  test "rejects an edit without a valid base revision" do
    assert {:ok, original} = Graphs.insert(graph("Topology"))

    attrs = %{"title" => original.title, "nodes" => [], "edges" => []}
    assert {:error, :invalid_base_revision} = Graphs.replace(original.id, attrs)

    assert {:error, :invalid_base_revision} =
             Graphs.replace(original.id, Map.put(attrs, "revision_id", Ecto.UUID.generate()))
  end

  test "optimization appends a revision to the same graph" do
    assert {:ok, original} = Graphs.insert(graph("Topology"))
    assert {:ok, optimized} = Graphs.append_optimization(original)

    assert %{revision_number: 2, revision_kind: :optimization} = optimized
    assert optimized.id == original.id
    assert optimized.parent_revision_id == original.revision_id
    assert Enum.map(Graph.nodes(optimized), & &1.id) == Enum.map(Graph.nodes(original), & &1.id)
  end

  test "returns an error for invalid snapshot endpoints" do
    assert {:ok, original} = Graphs.insert(graph("Topology"))
    [edge] = Graph.edges(original)

    assert {:error, :invalid_endpoints} =
             Graph.hydrate(original, Graph.nodes(original), [
               %{edge | to_id: Ecto.UUID.generate()}
             ])

    assert %{revision_number: 1} = Graphs.load_revision!(original.revision_id)
  end

  test "rejects duplicate snapshot node and edge IDs" do
    assert {:ok, original} = Graphs.insert(graph("Topology"))
    [host, service] = Graph.nodes(original)
    [edge] = Graph.edges(original)

    assert {:error, :duplicate_ids} =
             Graphs.replace(original.id, %{
               "title" => original.title,
               "revision_id" => original.revision_id,
               "nodes" => [node_attrs(host), node_attrs(host)],
               "edges" => []
             })

    assert {:error, :duplicate_ids} =
             Graphs.replace(original.id, %{
               "title" => original.title,
               "revision_id" => original.revision_id,
               "nodes" => [node_attrs(host), node_attrs(service)],
               "edges" => [edge_attrs(edge), edge_attrs(edge)]
             })
  end

  test "lists every revision with its lineage and snapshot counts" do
    assert {:ok, original} = Graphs.insert(graph_with_duplicate_edge("Topology"))
    assert {:ok, %{graph: edited}} = Graphs.replace(original.id, replacement_attrs(original))
    assert {:ok, optimized} = Graphs.append_optimization(edited)

    [initial, edit, optimization] =
      Graphs.list_summaries() |> Enum.filter(&(&1.graphId == original.id))

    assert %{
             graphId: graph_id,
             revisionId: initial_id,
             parentRevisionId: nil,
             revisionKind: "initial"
           } = initial

    assert graph_id == original.id
    assert initial_id == original.revision_id

    assert %{parentRevisionId: ^initial_id, revisionKind: "edit", nodeCount: 2, edgeCount: 2} =
             edit

    assert %{parentRevisionId: edit_id, revisionKind: "optimization", nodeCount: 2, edgeCount: 2} =
             optimization

    assert edit_id == edited.revision_id
    assert optimization.revisionId == optimized.revision_id
  end

  test "rejects identities owned by another graph" do
    assert {:ok, first} = Graphs.insert(graph("First"))
    [node | _] = Graph.nodes(first)
    second = Graph.new("Second")
    second = Graph.add_node(second, %{node | graph_id: second.id})

    assert {:error, :identity_belongs_to_another_graph} = Graphs.insert(second)
  end

  test "database rejects graph revision references from another graph" do
    assert {:ok, first} = Graphs.insert(graph("First"))
    assert {:ok, second} = Graphs.insert(graph("Second"))
    [_first_host, first_service] = Graph.nodes(first)
    [second_host | _] = Graph.nodes(second)

    assert_foreign_key_violation(
      """
      INSERT INTO graph_revisions (id, graph_id, parent_revision_id, number, kind, title, inserted_at, updated_at)
      VALUES ($1, $2, $3, 2, 'edit', 'Invalid parent', now(), now())
      """,
      [uuid(Ecto.UUID.generate()), uuid(second.id), uuid(first.revision_id)]
    )

    assert_foreign_key_violation(
      """
      INSERT INTO graph_revision_nodes (graph_revision_id, graph_id, node_id, type, data, view_data)
      VALUES ($1, $2, $3, $4, $5, $6)
      """,
      [
        uuid(first.revision_id),
        uuid(first.id),
        uuid(second_host.id),
        Atom.to_string(second_host.type),
        NetworkDefense.Graph.Data.to_params(second_host.data),
        second_host.view_data
      ]
    )

    edge_id = Ecto.UUID.generate()

    Repo.insert_all("edges", [
      %{
        id: uuid(edge_id),
        graph_id: uuid(first.id),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ])

    assert_foreign_key_violation(
      """
      INSERT INTO graph_revision_edges (graph_revision_id, graph_id, edge_id, from_id, to_id, type, data)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      """,
      [
        uuid(first.revision_id),
        uuid(first.id),
        uuid(edge_id),
        uuid(second_host.id),
        uuid(first_service.id),
        Atom.to_string(Runs),
        %{}
      ]
    )
  end

  test "database requires edge endpoints in the same revision" do
    assert {:ok, graph} = Graphs.insert(graph("Topology"))
    [host | _] = Graph.nodes(graph)
    missing_node_id = Ecto.UUID.generate()
    edge_id = Ecto.UUID.generate()

    now = DateTime.utc_now()

    Repo.insert_all("nodes", [
      %{id: uuid(missing_node_id), graph_id: uuid(graph.id), inserted_at: now, updated_at: now}
    ])

    Repo.insert_all("edges", [
      %{id: uuid(edge_id), graph_id: uuid(graph.id), inserted_at: now, updated_at: now}
    ])

    assert_foreign_key_violation(
      """
      INSERT INTO graph_revision_edges (graph_revision_id, graph_id, edge_id, from_id, to_id, type, data)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      """,
      [
        uuid(graph.revision_id),
        uuid(graph.id),
        uuid(edge_id),
        uuid(missing_node_id),
        uuid(host.id),
        Atom.to_string(Runs),
        %{}
      ]
    )
  end

  test "database enforces revision number, kind, and parent shape" do
    assert {:ok, graph} = Graphs.insert(graph("Topology"))

    assert_unique_violation(
      """
      INSERT INTO graph_revisions (id, graph_id, number, kind, title, inserted_at, updated_at)
      VALUES ($1, $2, 1, 'initial', 'Duplicate number', now(), now())
      """,
      [uuid(Ecto.UUID.generate()), uuid(graph.id)]
    )

    assert_check_violation(
      """
      INSERT INTO graph_revisions (id, graph_id, number, kind, title, inserted_at, updated_at)
      VALUES ($1, $2, 0, 'initial', 'Invalid number', now(), now())
      """,
      [uuid(Ecto.UUID.generate()), uuid(graph.id)]
    )

    assert_check_violation(
      """
      INSERT INTO graph_revisions (id, graph_id, number, kind, title, inserted_at, updated_at)
      VALUES ($1, $2, 2, 'invalid', 'Invalid kind', now(), now())
      """,
      [uuid(Ecto.UUID.generate()), uuid(graph.id)]
    )

    assert_check_violation(
      """
      INSERT INTO graph_revisions (id, graph_id, parent_revision_id, number, kind, title, inserted_at, updated_at)
      VALUES ($1, $2, $3, 2, 'initial', 'Initial parent', now(), now())
      """,
      [uuid(Ecto.UUID.generate()), uuid(graph.id), uuid(graph.revision_id)]
    )

    assert_check_violation(
      """
      INSERT INTO graph_revisions (id, graph_id, number, kind, title, inserted_at, updated_at)
      VALUES ($1, $2, 2, 'edit', 'Missing parent', now(), now())
      """,
      [uuid(Ecto.UUID.generate()), uuid(graph.id)]
    )
  end

  test "database rejects graph snapshot updates" do
    assert {:ok, graph} = Graphs.insert(graph("Topology"))
    [node | _] = Graph.nodes(graph)
    [edge] = Graph.edges(graph)

    assert_update_guard("UPDATE graph_revisions SET title = 'changed' WHERE id = $1", [
      uuid(graph.revision_id)
    ])

    assert_update_guard(
      "UPDATE graph_revision_nodes SET data = '{}' WHERE graph_revision_id = $1 AND node_id = $2",
      [uuid(graph.revision_id), uuid(node.id)]
    )

    assert_update_guard(
      "UPDATE graph_revision_edges SET data = '{}' WHERE graph_revision_id = $1 AND edge_id = $2",
      [uuid(graph.revision_id), uuid(edge.id)]
    )
  end

  test "deleting a graph cascades through its revisions and simulation history" do
    assert {:ok, graph} = Graphs.insert(graph("Topology"))
    [node | _] = Graph.nodes(graph)
    experiment_id = Ecto.UUID.generate()
    run_id = Ecto.UUID.generate()
    step_id = Ecto.UUID.generate()

    Repo.insert_all("experiments", [
      %{
        id: uuid(experiment_id),
        graph_revision_id: uuid(graph.revision_id),
        master_seed: 0,
        iteration_count: 1,
        max_attempts: 1,
        runtime_ms: 0,
        total_trials: 1,
        completed_trials: 0,
        status: "running",
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ])

    Repo.insert_all("simulation_runs", [
      %{
        id: uuid(run_id),
        experiment_id: uuid(experiment_id),
        graph_revision_id: uuid(graph.revision_id),
        seed: 0,
        trial_index: 0,
        initial_attacker_state: %{},
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ])

    Repo.insert_all("iteration_steps", [
      %{
        id: uuid(step_id),
        run_id: uuid(run_id),
        index: 1,
        success: true,
        attacker_state: %{},
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }
    ])

    Repo.delete!(Repo.get!(Graph, graph.id))

    assert Repo.get(Graph, graph.id) == nil
    assert Repo.get(GraphRevision, graph.revision_id) == nil
    assert Repo.get(Experiment, experiment_id) == nil
    assert Repo.get(Run, run_id) == nil
    assert Repo.get(IterationStep, step_id) == nil

    assert Repo.one(from(n in "nodes", where: n.id == ^Ecto.UUID.dump!(node.id), select: n.id)) ==
             nil
  end

  defp graph(title) do
    graph = Graph.new(title)

    host =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => "host"},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    service =
      Node.new(graph.id, %{
        type: Atom.to_string(Service),
        data: %{"name" => "ssh", "protocol" => "tcp", "port" => 22},
        view_data: %{"x_pos" => 100, "y_pos" => 0}
      })

    graph
    |> Graph.add_node(host)
    |> Graph.add_node(service)
    |> Graph.add_edge(
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}})
    )
  end

  defp graph_with_duplicate_edge(title) do
    graph = graph(title)
    [host, service] = Graph.nodes(graph)

    Graph.add_edge(
      graph,
      Edge.new(graph.id, host.id, service.id, %{type: Atom.to_string(Runs), data: %{}})
    )
  end

  defp node_attrs(node) do
    %{
      "id" => node.id,
      "type" => Atom.to_string(node.type),
      "data" => NetworkDefense.Graph.Data.to_params(node.data),
      "view_data" => %{"x_pos" => node.view_data.x_pos, "y_pos" => node.view_data.y_pos}
    }
  end

  defp replacement_attrs(graph) do
    [host, service] = Graph.nodes(graph)

    %{
      "title" => graph.title,
      "revision_id" => graph.revision_id,
      "nodes" => [node_attrs(host), node_attrs(service)],
      "edges" => Enum.map(Graph.edges(graph), &edge_attrs/1)
    }
  end

  defp edge_attrs(edge) do
    %{
      "id" => edge.id,
      "from_id" => edge.from_id,
      "to_id" => edge.to_id,
      "type" => Atom.to_string(edge.type),
      "data" => NetworkDefense.Graph.Data.to_params(edge.data)
    }
  end

  defp assert_foreign_key_violation(query, params) do
    assert {:error, %Postgrex.Error{postgres: %{code: :foreign_key_violation}}} =
             Repo.query(query, params)
  end

  defp assert_update_guard(query, params) do
    assert {:error, %Postgrex.Error{postgres: %{code: :raise_exception}}} =
             Repo.query(query, params)
  end

  defp assert_unique_violation(query, params) do
    assert {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} =
             Repo.query(query, params)
  end

  defp assert_check_violation(query, params) do
    assert {:error, %Postgrex.Error{postgres: %{code: :check_violation}}} =
             Repo.query(query, params)
  end

  defp uuid(id), do: Ecto.UUID.dump!(id)
end
