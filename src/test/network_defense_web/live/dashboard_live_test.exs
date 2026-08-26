defmodule NetworkDefenseWeb.DashboardLiveTest do
  use NetworkDefenseWeb.ConnCase
  use Oban.Testing, repo: NetworkDefense.Repo

  import Phoenix.LiveViewTest

  alias NetworkDefense.Evaluation.EvaluationWorker
  alias NetworkDefense.EvaluationFixtures
  alias NetworkDefense.Graph.{Edge, Folders, Graph}
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.NetworkSegment
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Optimizations.OptimizationWorker
  alias NetworkDefense.Relationships.Contains
  alias NetworkDefense.Relationships.NetworkReachability
  alias NetworkDefense.Relationships.Runs
  alias NetworkDefense.Relationships.SegmentReachability
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulations
  alias NetworkDefense.Simulations.SimulationWorker

  describe "evaluation manifests" do
    @valid_manifest EvaluationFixtures.valid_manifest()

    test "saves, lists, and gets a manifest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      manifest_id = "fixed-enterprise-#{System.unique_integer([:positive])}"
      manifest = Map.put(@valid_manifest, "id", manifest_id)

      render_hook(view, "save_manifest", %{
        "manifest_id" => manifest_id,
        "title" => "Fixed enterprise",
        "content" => manifest
      })

      assert_reply(view, %{
        status: "ok",
        manifest: %{
          id: manifest_record_id,
          manifest_id: ^manifest_id,
          title: "Fixed enterprise"
        }
      })

      render_hook(view, "list_manifests", %{})
      assert_reply(view, %{manifests: manifests})
      assert Enum.any?(manifests, &(&1.manifest_id == manifest_id))

      render_hook(view, "get_manifest", %{"id" => manifest_record_id})
      assert_reply(view, %{manifest: %{id: ^manifest_record_id, content: content}})
      assert content["id"] == manifest_id
    end

    test "accepts unknown manifest fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      manifest_id = "fixed-enterprise-#{System.unique_integer([:positive])}"

      render_hook(view, "save_manifest", %{
        "manifest_id" => manifest_id,
        "title" => "Fixed enterprise",
        "content" => @valid_manifest |> Map.put("id", manifest_id) |> Map.put("bogus", 1)
      })

      assert_reply(view, %{status: "ok"})
    end

    test "describes an editor manifest without persisting it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "describe_manifest", %{"content" => @valid_manifest})

      assert_reply(view, %{
        status: "ok",
        plans: plans,
        comparison_groups: comparison_groups,
        errors: []
      })

      assert [%{model_variant: "full", strategy: "cvss", budget: 1, selection_seed: 102}] =
               Enum.filter(plans, &(&1.strategy == "cvss"))

      assert [group] = comparison_groups

      assert group == %{
               index: 0,
               tested: %{
                 model_variant: "full",
                 strategy: "cvss",
                 budget: 1,
                 selection_seeds: [102]
               },
               baseline: %{
                 model_variant: "full",
                 strategy: "null",
                 budget: 1,
                 selection_seeds: [101]
               },
               outcome: "blast_radius"
             }
    end

    test "describes a manifest without touching the database", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      before = NetworkDefense.Evaluation.list() |> length()

      render_hook(view, "describe_manifest", %{"content" => @valid_manifest})
      assert_reply(view, %{status: "ok"})

      assert NetworkDefense.Evaluation.list() |> length() == before
    end

    test "rejects an invalid editor manifest with its validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "describe_manifest", %{"content" => %{"bad" => 1}})

      assert_reply(view, %{
        status: "invalid_manifest",
        plans: [],
        comparison_groups: [],
        errors: errors
      })

      assert Enum.any?(errors, &(&1.path == "schema_version"))
    end

    test "rejects a describe_manifest payload without a content map", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "describe_manifest", %{})
      assert_reply(view, %{status: "invalid_request", plans: [], errors: []})

      render_hook(view, "describe_manifest", %{"content" => ["not", "a", "map"]})
      assert_reply(view, %{status: "invalid_request"})
    end

    test "starts an evaluation for a saved manifest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      manifest_id = "fixed-enterprise-#{System.unique_integer([:positive])}"

      manifest =
        @valid_manifest
        |> Map.put("id", manifest_id)
        |> put_in(["evaluation", "trials"], 1)

      render_hook(view, "save_manifest", %{
        "manifest_id" => manifest_id,
        "title" => "Fixed enterprise",
        "content" => manifest
      })

      assert_reply(view, %{status: "ok"})

      render_hook(view, "start_evaluation", %{"manifest_id" => manifest_id})

      assert_reply(view, %{status: "accepted", run_id: run_id})
      assert is_binary(run_id)
      assert has_element?(view, "#flash-info[role='alert']")

      assert run_id == perform_evaluation_job()

      assert_push_event(view, "evaluation_completed", %{run_id: ^run_id})
    end

    test "returns not_found for an unknown manifest", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "start_evaluation", %{"manifest_id" => "nope"})

      assert_reply(view, %{status: "not_found", run_id: nil})
    end

    test "rejects and fails the run when the evaluation job cannot be enqueued", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      manifest_id = "fixed-enterprise-#{System.unique_integer([:positive])}"

      manifest =
        @valid_manifest
        |> Map.put("id", manifest_id)
        |> put_in(["evaluation", "trials"], 1)

      render_hook(view, "save_manifest", %{
        "manifest_id" => manifest_id,
        "title" => "Fixed enterprise",
        "content" => manifest
      })

      assert_reply(view, %{status: "ok", manifest: %{id: manifest_record_id}})

      :meck.new(Oban, [:passthrough])
      :meck.expect(Oban, :insert, fn _name, _changeset -> {:error, :unavailable} end)

      render_hook(view, "start_evaluation", %{"manifest_id" => manifest_id})

      assert_reply(view, %{status: "rejected", run_id: nil})

      assert [%{status: "failed", failure_reason: "task_unavailable"}] =
               NetworkDefense.Evaluation.EvaluationRuns.list_by_manifest(manifest_record_id)
               |> Enum.filter(&(&1.status == "failed"))
    after
      :meck.unload(Oban)
    end

    test "forwards evaluation report assembly progress events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      run_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:evaluation_report_progress, run_id, "graph-1", "revision-1", 1, 4,
         "Loading source graph"}
      )

      assert_push_event(view, "evaluation_report_progress", %{
        correlation_id: ^run_id,
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        completed: 1,
        total: 4,
        detail: "Loading source graph"
      })
    end

    test "forwards simulation report assembly progress events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      experiment_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:simulation_report_progress, experiment_id, "graph-1", "revision-1", 4, 6,
         "Materializing operational flows"}
      )

      assert_push_event(view, "simulation_report_progress", %{
        correlation_id: ^experiment_id,
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        completed: 4,
        total: 6,
        detail: "Materializing operational flows"
      })
    end

    test "forwards optimization report assembly progress events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      optimization_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:optimization_report_progress, optimization_id, "graph-1", "revision-1", 2, 2,
         "Building action summaries"}
      )

      assert_push_event(view, "optimization_report_progress", %{
        correlation_id: ^optimization_id,
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        completed: 2,
        total: 2,
        detail: "Building action summaries"
      })
    end

    test "forwards a fetched evaluation report as a ready event", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      document_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      report = %{
        run_id: run_id,
        status: "completed",
        failure_reason: nil,
        manifest_id: "fixed-enterprise-v1",
        manifest_title: "Fixed enterprise",
        graph_id: Ecto.UUID.generate(),
        source_graph_revision_id: Ecto.UUID.generate(),
        source_graph_title: "Source graph",
        plans: [],
        experiments: []
      }

      send(view.pid, {:evaluation_report_result, document_id, run_id, {:ok, report}})

      assert_push_event(view, "evaluation_report_ready", %{
        document_id: ^document_id,
        report: ^report
      })
    end

    test "maps a missing evaluation run to not_found, not an internal error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      document_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:evaluation_report_result, document_id, run_id, {:error, {:not_found, nil}}}
      )

      assert_push_event(view, "evaluation_report_error", %{
        document_id: ^document_id,
        run_id: ^run_id,
        error: %{code: "not_found"}
      })
    end

    test "maps a failed report fetch to an internal error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      document_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:evaluation_report_result, document_id, run_id,
         {:error, {:internal_error, "connection lost"}}}
      )

      assert_push_event(view, "evaluation_report_error", %{
        document_id: ^document_id,
        run_id: ^run_id,
        error: %{code: "internal_error"}
      })
    end

    test "rejects invalid evaluation analysis parameters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "request_evaluation_analysis", %{})
      assert_reply(view, %{status: "invalid_params"})

      render_hook(view, "request_evaluation_analysis", %{
        "document_id" => Ecto.UUID.generate(),
        "run_id" => Ecto.UUID.generate(),
        "mode" => "invalid"
      })

      assert_reply(view, %{status: "invalid_params"})
    end

    test "processes an analysis request and reports an unknown run", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      render_hook(view, "request_evaluation_analysis", %{
        "document_id" => document_id,
        "run_id" => run_id,
        "mode" => "pilot"
      })

      assert_reply(view, %{status: "processing"})

      assert_push_event(view, "evaluation_analysis_error", %{
        document_id: ^document_id,
        run_id: ^run_id,
        mode: "pilot",
        error: %{code: "not_found"}
      })
    end

    test "pushes typed evaluation analysis ready and error events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      document_id = Ecto.UUID.generate()
      run_id = Ecto.UUID.generate()

      analysis = %{
        metadata: %{
          manifest_id: "manifest-1",
          schema_version: 1,
          model_version: "model-1",
          command_mode: "pilot"
        },
        pilot_comparison_pass: [],
        primary_results: [],
        secondary_results: [],
        capability_results: []
      }

      send(view.pid, {:evaluation_analysis_result, document_id, run_id, "pilot", {:ok, analysis}})

      assert_push_event(view, "evaluation_analysis_ready", %{
        document_id: ^document_id,
        run_id: ^run_id,
        mode: "pilot",
        analysis: %{metadata: %{manifest_id: "manifest-1"}}
      })

      send(
        view.pid,
        {:evaluation_analysis_result, document_id, run_id, "analyze", {:error, :not_found}}
      )

      assert_push_event(view, "evaluation_analysis_error", %{
        document_id: ^document_id,
        run_id: ^run_id,
        mode: "analyze",
        error: %{code: "not_found"}
      })
    end

    test "forwards evaluation progress events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      progress = %{
        correlation_id: "evaluation-1",
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        completed: 0,
        total: 7,
        detail: "Selecting plans"
      }

      send(view.pid, {:evaluation_progress, progress})
      assert_push_event(view, "evaluation_progress", ^progress)

      batch_progress = %{
        correlation_id: "evaluation-1",
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        completed: 4,
        total: 7,
        detail: "Baseline attack trials: 3 of 3"
      }

      send(view.pid, {:evaluation_progress, batch_progress})
      assert_push_event(view, "evaluation_progress", ^batch_progress)
    end
  end

  describe "mount" do
    test "renders the Svelte dashboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "renders an accessible loading state while the client dashboard mounts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#dashboard [role='status'].dashboard-loading")
    end

    test "renders hidden recovery flashes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#client-error[hidden][phx-disconnected][phx-connected]")
      assert has_element?(view, "#server-error[hidden][phx-disconnected][phx-connected]")
    end
  end

  describe "fetch_graph_connectivity" do
    test "returns backend semantic connectivity rules", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_graph_connectivity", %{})

      assert_reply(view, %{rules: rules})

      assert %{from_type: "Host", relationship_type: "Runs", to_type: "Service"} in rules
    end
  end

  describe "fetch_document_catalog" do
    test "returns persisted graph revisions as catalog items", %{conn: conn} do
      graph = insert_graph("catalog-graph")
      graph_id = graph.id
      graph_revision_id = graph.revision_id

      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "fetch_document_catalog", %{"limit" => 1, "offset" => 0})

      assert_reply(view, %{items: items, total_count: total_count, filter_options: filter_options})

      assert total_count >= 1

      assert %{
               types: _types,
               graphs: _graphs,
               strategies: _strategies,
               revision_kinds: _revision_kinds
             } = filter_options

      assert %{
               id: ^graph_revision_id,
               kind: "graph",
               graph_id: ^graph_id,
               graph_revision_id: ^graph_revision_id,
               graph_title: "catalog-graph",
               revision_kind: "initial",
               revision_number: 1,
               strategy: nil,
               output_graph_revision_id: nil,
               output_revision_kind: nil,
               output_revision_number: nil,
               created_at: _created_at
             } = Enum.find(items, &(&1.id == graph_revision_id))
    end

    test "replies directly to consecutive catalog queries", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_document_catalog", %{"limit" => 1, "offset" => 0})
      assert_reply(view, %{items: _items, total_count: _total_count})

      render_hook(view, "fetch_document_catalog", %{"limit" => 1, "offset" => 1})
      assert_reply(view, %{items: _items, total_count: _total_count})
    end
  end

  describe "graph drafts" do
    test "returns a validated node draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "create_node_draft", %{
        "node_type" => "Host",
        "x_pos" => 30,
        "y_pos" => 40
      })

      assert_reply(view, %{
        status: "ok",
        node: %{type: "Host", data: %{name: "New host"}, view_data: %{x_pos: 30.0, y_pos: 40.0}}
      })
    end

    test "returns a reverse-directed connection draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      service_id = Ecto.UUID.generate()
      host_id = Ecto.UUID.generate()

      render_hook(view, "create_connection_draft", %{
        "relationship_type" => "Runs",
        "source_id" => service_id,
        "source_type" => "Service",
        "source_is_from" => false,
        "target_id" => host_id,
        "target_type" => "Host"
      })

      assert_reply(view, %{
        status: "ok",
        edge: %{type: "Runs", from_id: ^host_id, to_id: ^service_id, data: %{}}
      })
    end

    test "rejects an invalid connection draft", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "create_connection_draft", %{
        "relationship_type" => "Runs",
        "source_id" => Ecto.UUID.generate(),
        "source_type" => "Service",
        "source_is_from" => true,
        "target_id" => Ecto.UUID.generate(),
        "target_type" => "Host"
      })

      assert_reply(view, %{status: "invalid", edge: nil, node: nil})
    end
  end

  describe "open_graph" do
    test "accepts an existing graph", %{conn: conn} do
      graph = insert_graph("dwg-001")
      source = insert_node(graph, "origin")
      target = insert_service(Graphs.load_revision!(source.graph_revision_id), "dest")
      graph = Graphs.load_revision!(target.graph_revision_id)

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{"graph_revision_id" => graph.revision_id})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts a missing graph_revision_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{
        "graph_revision_id" => "00000000-0000-0000-0000-000000000000"
      })

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "accepts an open request without graph_revision_id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "open_graph", %{})

      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end
  end

  describe "set_graph_revision_favorite" do
    test "updates a graph revision favorite", %{conn: conn} do
      graph = insert_graph("favorite")
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "set_graph_revision_favorite", %{
        "graph_revision_id" => graph.revision_id,
        "favorite" => true
      })

      assert_reply(view, %{status: "ok", favorite: true})

      assert %{isFavorite: true} =
               Graphs.list_summaries() |> Enum.find(&(&1.revisionId == graph.revision_id))

      render_hook(view, "set_graph_revision_favorite", %{
        "graph_revision_id" => graph.revision_id,
        "favorite" => false
      })

      assert_reply(view, %{status: "ok", favorite: false})

      assert %{isFavorite: false} =
               Graphs.list_summaries() |> Enum.find(&(&1.revisionId == graph.revision_id))
    end

    test "rejects an invalid graph revision favorite request", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "set_graph_revision_favorite", %{"favorite" => true})

      assert_reply(view, %{status: "invalid_graph", favorite: false})
    end
  end

  describe "graph folders" do
    test "creates a folder and moves every graph revision into it", %{conn: conn} do
      graph = insert_graph("foldered")
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "create_folder", %{"name" => "Threat models"})

      assert_reply(view, %{status: "ok", folder: %{id: folder_id, name: "Threat models"}})

      render_hook(view, "move_graph_to_folder", %{
        "graph_id" => graph.id,
        "folder_id" => folder_id
      })

      assert_reply(view, %{status: "ok"})

      assert %{folderId: ^folder_id} =
               Graphs.list_summaries() |> Enum.find(&(&1.graphId == graph.id))
    end

    test "deleting a folder returns its graphs to the root", %{conn: conn} do
      graph = insert_graph("unfoldered")
      assert {:ok, folder} = Folders.create("Temporary")
      assert {:ok, _graph} = Folders.move_graph(graph.id, folder.id)
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "delete_folder", %{"folder_id" => folder.id})

      assert_reply(view, %{status: "ok"})
      assert %{folderId: nil} = Graphs.list_summaries() |> Enum.find(&(&1.graphId == graph.id))
    end

    test "rejects invalid folder requests", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "create_folder", %{"name" => ""})
      assert_reply(view, %{status: "invalid_folder", folder: nil})

      render_hook(view, "move_graph_to_folder", %{"graph_id" => "not-a-uuid"})
      assert_reply(view, %{status: "invalid_graph"})
    end
  end

  describe "compare_graphs" do
    test "rejects an invalid base graph", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "compare_graphs", %{})

      assert_reply(view, %{status: "invalid_graph", result: nil})
    end

    test "reports a missing comparison revision", %{conn: conn} do
      base = insert_graph("base")
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "compare_graphs", %{
        "base_revision_id" => base.revision_id,
        "comparison_revision_id" => "00000000-0000-0000-0000-000000000000"
      })

      assert_reply(view, %{status: "not_found", result: nil})
    end

    test "returns a merged structural result for two persisted revisions", %{conn: conn} do
      base = insert_graph("base")
      source = insert_node(base, "source")
      target = insert_service(Graphs.load_revision!(source.graph_revision_id), "target")
      base = Graphs.load_revision!(target.graph_revision_id)
      assert {:ok, comparison} = Graphs.append_optimization(%{base | title: "comparison"})

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "compare_graphs", %{
        "base_revision_id" => base.revision_id,
        "comparison_revision_id" => comparison.revision_id
      })

      assert_reply(view, %{
        status: "ok",
        result: %{
          graph: %{id: result_graph_id, title: "base"},
          node_counts: %{added: 0, removed: 0, unchanged: 3},
          edge_counts: %{added: 0, removed: 0, unchanged: 2},
          node_status: node_status,
          edge_status: edge_status
        }
      })

      assert result_graph_id == base.id
      assert Enum.all?(node_status, &(&1.status == "unchanged"))
      assert Enum.all?(edge_status, &(&1.status == "unchanged"))
    end

    test "reports a persisted SegmentReachability removal as one edge-level removal", %{
      conn: conn
    } do
      graph = insert_graph("compare-policy-removal")
      source = insert_node(graph, "source")
      graph = Graphs.load_revision!(source.graph_revision_id)
      target = insert_service(graph, "target")
      graph = Graphs.load_revision!(target.graph_revision_id)
      segment = Enum.find(Graph.nodes(graph), &(&1.type == NetworkSegment))
      other_segment = insert_segment(graph, "other")
      graph = Graphs.load_revision!(other_segment.graph_revision_id)
      policy_id = Ecto.UUID.generate()

      assert {:ok, graph} =
               Graphs.append_optimization(
                 Graph.add_edge(graph, %{
                   Edge.new(graph.id, segment.id, other_segment.id, %{
                     type: Atom.to_string(SegmentReachability),
                     data: %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
                   })
                   | id: policy_id
                 })
               )

      assert {:ok, comparison} =
               Graphs.append_optimization(Graph.remove_edge_by_id(graph, policy_id))

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "compare_graphs", %{
        "base_revision_id" => graph.revision_id,
        "comparison_revision_id" => comparison.revision_id
      })

      assert_reply(view, %{
        status: "ok",
        result: %{
          graph: %{edges: wire_edges},
          edge_counts: %{added: 0, removed: 1, unchanged: 2},
          edge_status: edge_status
        }
      })

      assert Enum.any?(edge_status, &(&1.id == policy_id and &1.status == "removed"))
      refute Enum.any?(edge_status, &(&1.status == "added"))
      refute Enum.any?(wire_edges, &(&1.type == "NetworkReachability"))
    end
  end

  describe "simulation events" do
    test "returns invalid_params for an invalid report request", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_simulation_report", %{})

      assert_reply(view, %{status: "invalid_params"})
    end

    test "returns a report pinned to the experiment's graph revision", %{conn: conn} do
      graph = insert_graph("versioned-report")
      foothold = insert_node(graph, "entry-host")
      foothold_revision_id = foothold.graph_revision_id
      correlation_id = "versioned-report-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => foothold.graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true
          }
        }
      })

      perform_simulation_job()

      assert_receive {:simulation_completed,
                      %{correlation_id: ^correlation_id, experiment_id: experiment_id}},
                     5_000

      assert {:ok, _revised} =
               Graphs.append_optimization(%{
                 Graphs.load_revision!(foothold.graph_revision_id)
                 | title: "changed topology"
               })

      document_id = Ecto.UUID.generate()

      render_hook(view, "fetch_simulation_report", %{
        "document_id" => document_id,
        "experiment_id" => experiment_id
      })

      assert_reply(view, %{status: "processing"})

      assert_push_event(view, "simulation_report_ready", %{
        document_id: ^document_id,
        report: %{experiment_id: ^experiment_id, graph_revision_id: ^foothold_revision_id}
      })
    end

    test "accepts a correlated simulation request and broadcasts its completion", %{conn: conn} do
      graph = insert_graph("run-sim-test")
      graph_id = graph.id
      foothold = insert_node(graph, "entry-host")
      correlation_id = "request-123"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => foothold.graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true
          }
        }
      })

      assert_reply(view, %{
        status: "accepted",
        graph_revision_id: graph_revision_id,
        correlation_id: ^correlation_id,
        error: nil
      })

      assert has_element?(view, "#flash-info[role='alert']")

      perform_simulation_job()

      assert_receive {:simulation_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        graph_revision_id: ^graph_revision_id,
                        experiment_id: experiment_id
                      }},
                     5_000

      assert is_binary(experiment_id)
      assert has_element?(view, "#dashboard[data-name='DashboardHost']")
    end

    test "lists completed experiments with their master seed", %{conn: conn} do
      graph = insert_graph("experiment-list")
      foothold = insert_node(graph, "entry-host")
      graph_revision_id = foothold.graph_revision_id
      correlation_id = "experiment-list-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true
          }
        }
      })

      perform_simulation_job()

      assert_receive {:simulation_completed,
                      %{correlation_id: ^correlation_id, experiment_id: experiment_id}},
                     5_000

      render_hook(view, "fetch_experiments", %{
        "graph_revision_ids" => [graph_revision_id]
      })

      assert_reply(view, %{
        experiments: [
          %{
            id: ^experiment_id,
            graph_revision_id: ^graph_revision_id,
            seed: seed
          }
        ]
      })

      assert seed == Experiments.get(experiment_id).master_seed
    end

    test "commits a simulation across trial batches", %{conn: conn} do
      graph = insert_graph("batched-simulation")
      foothold = insert_node(graph, "entry-host")
      correlation_id = "batched-simulation-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Simulations.simulation_events_topic())

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => foothold.graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 101,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true
          }
        }
      })

      perform_simulation_job()

      assert_receive {:simulation_completed,
                      %{correlation_id: ^correlation_id, experiment_id: experiment_id}},
                     5_000

      assert %{status: "completed", total_trials: 101, completed_trials: 101} =
               Experiments.get(experiment_id)
    end

    test "rejects a simulation request with nil seed and generate_seed false", %{conn: conn} do
      graph = insert_graph("nil-seed-test")
      graph_revision_id = graph.revision_id
      correlation_id = "request-nil-seed"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        error: %{code: "invalid_request"}
      })
    end

    test "rejects an invalid correlated simulation request", %{conn: conn} do
      correlation_id = "request-456"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{
        "request" => %{
          "graph_revision_id" => "not-a-uuid",
          "correlation_id" => correlation_id,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: "not-a-uuid",
        correlation_id: ^correlation_id,
        error: %{code: "invalid_request"}
      })
    end

    test "rejects a simulation request without valid parameters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_simulation_request", %{})

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: "",
        correlation_id: "",
        error: %{code: "invalid_request"}
      })
    end

    test "forwards simulation completion and failure events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      completed = %{
        correlation_id: "request-1",
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        experiment_id: "experiment-1"
      }

      send(view.pid, {:simulation_completed, completed})
      assert_push_event(view, "simulation_completed", ^completed)

      failed = %{
        correlation_id: "request-2",
        graph_id: "graph-2",
        graph_revision_id: "revision-2",
        reason: :persistence_failed
      }

      send(view.pid, {:simulation_failed, failed})

      assert_push_event(view, "simulation_failed", %{
        correlation_id: "request-2",
        graph_id: "graph-2",
        graph_revision_id: "revision-2",
        error: %{code: "persistence_failed"}
      })

      assert has_element?(view, "#flash-error[role='alert']")
    end
  end

  describe "optimization events" do
    test "accepts an optimization request and persists an optimized graph", %{conn: conn} do
      graph = insert_graph("optimize-test")
      foothold = insert_node(graph, "entry-host")
      graph = Graphs.load_revision!(foothold.graph_revision_id)
      graph_id = graph.id
      graph_revision_id = graph.revision_id
      correlation_id = "optimization-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "accepted",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        error: nil
      })

      assert has_element?(view, "#flash-info[role='alert']")

      assert graph_id == graph.id

      perform_optimization_job()

      assert_receive {:optimization_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        graph_revision_id: ^graph_revision_id,
                        output_graph_revision_id: optimized_revision_id,
                        optimization_id: optimization_id
                      }},
                     5_000

      assert is_binary(optimization_id)

      assert %{
               id: ^graph_id,
               parent_revision_id: ^graph_revision_id,
               revision_kind: :optimization,
               title: "optimize-test"
             } =
               Graphs.load_revision(optimized_revision_id)
    end

    test "rejects topology segmentation without reachability in the graph", %{conn: conn} do
      graph = insert_graph("topology-segmentation-test")
      foothold = insert_node(graph, "entry-host")
      graph = Graphs.load_revision!(foothold.graph_revision_id)
      graph_revision_id = graph.revision_id
      correlation_id = "topology-segmentation-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{
            "strategy" => "topology_segmentation",
            "budget" => 1,
            "simulation_params" => %{
              "monte_carlo_trials" => 1,
              "iterations_per_run" => 1,
              "initial_foothold_node_id" => foothold.id,
              "generate_seed" => true,
              "max_attempts" => 1
            }
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        error: %{code: "reachability_required"}
      })

      refute_received {:optimization_completed, _}
    end

    test "accepts simulated annealing optimization", %{conn: conn} do
      assert_strategy_optimization(
        conn,
        "simulated_annealing",
        "Simulation-informed simulated annealing strategy"
      )
    end

    test "optimizes a graph with the maximum title length", %{conn: conn} do
      graph = insert_graph(String.duplicate("x", 255))
      graph_id = graph.id
      graph_revision_id = graph.revision_id
      graph_title = graph.title
      correlation_id = "optimization-title-too-long"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "accepted",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        error: nil
      })

      perform_optimization_job()

      assert_receive {:optimization_completed,
                      %{
                        correlation_id: ^correlation_id,
                        graph_id: ^graph_id,
                        graph_revision_id: optimized_revision_id
                      }},
                     5_000

      assert %{title: ^graph_title} = Graphs.load_revision(optimized_revision_id)
    end

    test "rejects invalid optimization parameters", %{conn: conn} do
      graph = insert_graph("invalid-optimization")
      graph_revision_id = graph.revision_id
      correlation_id = "invalid-optimization-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 0}
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        error: %{code: "invalid_request"}
      })
    end

    test "requires simulation parameters for simulation-informed optimization", %{conn: conn} do
      graph = insert_graph("simulation-informed-optimization")
      graph_revision_id = graph.revision_id
      correlation_id = "simulation-informed-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "simulation_informed", "budget" => 1}
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        error: %{code: "invalid_request"}
      })
    end

    test "rejects a foothold that is not a host in the graph", %{conn: conn} do
      graph = insert_graph("invalid-foothold-optimization")
      graph_revision_id = graph.revision_id
      correlation_id = "invalid-foothold-request"

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{
            "strategy" => "topology_segmentation",
            "budget" => 1,
            "simulation_params" => %{
              "monte_carlo_trials" => 1,
              "iterations_per_run" => 1,
              "initial_foothold_node_id" => Ecto.UUID.generate(),
              "generate_seed" => true,
              "max_attempts" => 1
            }
          }
        }
      })

      assert_reply(view, %{
        status: "rejected",
        graph_revision_id: ^graph_revision_id,
        correlation_id: ^correlation_id,
        error: %{code: "invalid_initial_foothold"}
      })
    end

    test "forwards optimization completion and failure events", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      completed = %{
        correlation_id: "optimization-1",
        graph_id: "graph-1",
        graph_revision_id: "revision-1",
        output_graph_revision_id: "output-revision-1",
        optimization_id: "optimization-1"
      }

      send(view.pid, {:optimization_completed, completed})
      assert_push_event(view, "optimization_completed", ^completed)

      failed = %{
        correlation_id: "optimization-2",
        graph_id: "graph-2",
        graph_revision_id: "revision-2",
        reason: :internal_error
      }

      send(view.pid, {:optimization_failed, failed})

      assert_push_event(view, "optimization_failed", %{
        correlation_id: "optimization-2",
        graph_id: "graph-2",
        graph_revision_id: "revision-2",
        error: %{code: "internal_error"}
      })

      assert has_element?(view, "#flash-error[role='alert']")

      progress = %{
        correlation_id: "optimization-3",
        graph_id: "graph-3",
        graph_revision_id: "revision-3",
        completed: 1,
        total: 2,
        detail: "Applied defense 1 of 2"
      }

      send(view.pid, {:optimization_progress, progress})
      assert_push_event(view, "optimization_progress", ^progress)
    end
  end

  describe "optimization reports" do
    test "returns invalid_params for an invalid report request", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_optimization_report", %{})

      assert_reply(view, %{status: "invalid_params"})
    end

    test "returns a report pinned to the run's source graph revision", %{conn: conn} do
      graph = insert_graph("versioned-optimization-report")
      foothold = insert_node(graph, "entry-host")
      source_revision_id = Graphs.load_revision!(foothold.graph_revision_id).revision_id
      correlation_id = "versioned-optimization-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => source_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      perform_optimization_job()

      assert_receive {:optimization_completed,
                      %{correlation_id: ^correlation_id, optimization_id: optimization_id}},
                     5_000

      assert {:ok, _revised} =
               Graphs.append_optimization(%{
                 Graphs.load_revision!(source_revision_id)
                 | title: "changed topology"
               })

      document_id = Ecto.UUID.generate()

      render_hook(view, "fetch_optimization_report", %{
        "document_id" => document_id,
        "optimization_id" => optimization_id
      })

      assert_reply(view, %{status: "processing"})

      assert_push_event(view, "optimization_report_ready", %{
        document_id: ^document_id,
        report: %{
          optimization_id: ^optimization_id,
          graph_revision_id: ^source_revision_id,
          report: %{strategy: "cvss", requested_budget: 1, used_budget: 0, actions: []}
        }
      })
    end

    test "fetches a completed optimization report for its source revision", %{conn: conn} do
      graph = insert_graph("optimization-report")
      foothold = insert_node(graph, "entry-host")
      graph = Graphs.load_revision!(foothold.graph_revision_id)
      source_revision_id = graph.revision_id
      graph_id = graph.id
      correlation_id = "optimization-report-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => source_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      perform_optimization_job()

      assert_receive {:optimization_completed,
                      %{correlation_id: ^correlation_id, optimization_id: optimization_id}},
                     5_000

      document_id = Ecto.UUID.generate()

      render_hook(view, "fetch_optimization_report", %{
        "document_id" => document_id,
        "optimization_id" => optimization_id
      })

      assert_reply(view, %{status: "processing"})

      assert_push_event(view, "optimization_report_ready", %{
        document_id: ^document_id,
        report: %{
          optimization_id: ^optimization_id,
          graph_id: ^graph_id,
          graph_title: "optimization-report",
          graph_revision_id: ^source_revision_id,
          report: %{strategy: "cvss", requested_budget: 1, used_budget: 0, actions: []}
        }
      })
    end
  end

  describe "optimization runs" do
    test "lists completed optimization runs for submitted revisions", %{conn: conn} do
      graph = insert_graph("optimization-runs")
      foothold = insert_node(graph, "entry-host")
      graph = Graphs.load_revision!(foothold.graph_revision_id)
      graph_revision_id = graph.revision_id
      graph_id = graph.id
      correlation_id = "optimization-runs-request"

      {:ok, view, _html} = live(conn, ~p"/")
      Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

      render_hook(view, "run_optimization_request", %{
        "request" => %{
          "graph_revision_id" => graph_revision_id,
          "correlation_id" => correlation_id,
          "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
        }
      })

      perform_optimization_job()

      assert_receive {:optimization_completed,
                      %{correlation_id: ^correlation_id, optimization_id: optimization_id}},
                     5_000

      render_hook(view, "fetch_optimization_runs", %{
        "graph_revision_ids" => [graph_revision_id]
      })

      assert_reply(view, %{
        runs: [
          %{
            id: ^optimization_id,
            graph_id: ^graph_id,
            graph_revision_id: ^graph_revision_id,
            graph_title: "optimization-runs",
            strategy: "cvss",
            requested_budget: 1,
            used_budget: 0,
            runtime_ms: runtime_ms,
            output_graph_revision_id: output_revision_id,
            started_at: started_at
          }
        ]
      })

      assert is_integer(runtime_ms)
      assert is_binary(output_revision_id)
      assert is_binary(started_at)
    end

    test "returns an empty run list for unknown revisions", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_optimization_runs", %{
        "graph_revision_ids" => ["00000000-0000-0000-0000-000000000000"]
      })

      assert_reply(view, %{runs: []})
    end

    test "rejects invalid revision ids", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_optimization_runs", %{"graph_revision_ids" => ["not-a-uuid"]})

      assert_reply(view, %{runs: []})
    end
  end

  describe "fetch_runs" do
    test "returns active runs of every kind", %{conn: conn} do
      graph = insert_graph("active-runs")
      graph_revision_id = graph.revision_id

      experiment = insert_running_experiment(graph_revision_id)
      optimization = insert_running_optimization(graph_revision_id)
      evaluation = insert_running_evaluation()

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_runs", %{})

      assert_reply(view, %{runs: runs})

      assert MapSet.new(Enum.map(runs, & &1.kind)) ==
               MapSet.new(["simulation", "optimization", "evaluation"])

      assert %{
               id: ^experiment,
               kind: "simulation",
               title: "active-runs",
               status: "running",
               completed: 0,
               total: 10,
               started_at: started_at
             } = Enum.find(runs, &(&1.id == experiment))

      assert is_binary(started_at)

      assert %{id: ^optimization, kind: "optimization", status: "running"} =
               Enum.find(runs, &(&1.id == optimization))

      assert %{id: ^evaluation, kind: "evaluation", status: "running"} =
               Enum.find(runs, &(&1.id == evaluation))
    end

    test "omits completed and failed runs", %{conn: conn} do
      graph = insert_graph("inactive-runs")
      graph_revision_id = graph.revision_id

      insert_running_experiment(graph_revision_id)
      insert_completed_experiment(graph_revision_id)
      insert_failed_experiment(graph_revision_id)

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_runs", %{})

      assert_reply(view, %{runs: runs})
      assert Enum.all?(runs, &(&1.status == "running"))
      assert [_] = runs
    end
  end

  describe "fetch_graph_projection" do
    test "returns segments, hosts, policy links, and derived operational flows for a saved revision",
         %{
           conn: conn
         } do
      graph = insert_graph("projection")
      source = insert_node(graph, "source")
      graph = Graphs.load_revision!(source.graph_revision_id)
      target = insert_service(graph, "target")
      graph = Graphs.load_revision!(target.graph_revision_id)
      segment = Enum.find(Graph.nodes(graph), &(&1.type == NetworkSegment))
      host = Enum.find(Graph.nodes(graph), &(&1.type == Host))
      policy_id = Ecto.UUID.generate()

      assert {:ok, graph} =
               Graphs.append_optimization(
                 Graph.add_edge(
                   graph,
                   %{
                     Edge.new(graph.id, segment.id, segment.id, %{
                       type: Atom.to_string(SegmentReachability),
                       data: %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
                     })
                     | id: policy_id
                   }
                 )
               )

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_graph_projection", %{
        "graph_revision_id" => graph.revision_id
      })

      assert_reply(view, %{
        status: "ok",
        segments: [%{id: segment_id}],
        hosts: [%{id: host_id}],
        policy_links: [policy_link],
        operational_flows: [operational_flow]
      })

      assert segment_id == segment.id
      assert host_id == host.id

      assert %{id: ^policy_id, from_id: ^segment_id, to_id: ^segment_id} = policy_link

      target_id = target.id
      assert %{id: flow_id, from_id: ^host_id, to_id: ^target_id} = operational_flow
      assert {:ok, _uuid} = Ecto.UUID.cast(flow_id)

      refute Enum.any?(
               Graph.edges(Graphs.load_revision!(graph.revision_id)),
               &(&1.type == NetworkReachability)
             )
    end

    test "derives deterministic operational flow ids across repeated fetches", %{conn: conn} do
      graph = insert_graph("projection-determinism")
      source = insert_node(graph, "source")
      graph = Graphs.load_revision!(source.graph_revision_id)
      target = insert_service(graph, "target")
      graph = Graphs.load_revision!(target.graph_revision_id)
      graph_revision_id = graph.revision_id

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_graph_projection", %{"graph_revision_id" => graph_revision_id})
      assert_reply(view, %{operational_flows: first_flows})

      render_hook(view, "fetch_graph_projection", %{"graph_revision_id" => graph_revision_id})
      assert_reply(view, %{operational_flows: second_flows})

      assert Enum.map(first_flows, & &1.id) == Enum.map(second_flows, & &1.id)
    end

    test "returns not_found for an unknown revision", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_graph_projection", %{
        "graph_revision_id" => "00000000-0000-0000-0000-000000000000"
      })

      assert_reply(view, %{
        status: "not_found",
        segments: [],
        hosts: [],
        policy_links: [],
        operational_flows: []
      })
    end

    test "rejects a projection request without a revision id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_graph_projection", %{})

      assert_reply(view, %{
        status: "invalid_graph",
        segments: [],
        hosts: [],
        policy_links: [],
        operational_flows: []
      })
    end

    test "rejects a projection request with a non-UUID revision id", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "fetch_graph_projection", %{"graph_revision_id" => "not-a-uuid"})

      assert_reply(view, %{status: "invalid_graph"})
    end
  end

  describe "save_graph" do
    test "persists a fully owned canonical graph with segment policy", %{conn: conn} do
      graph = insert_graph("save-graph")
      source = insert_node(graph, "source")
      graph = Graphs.load_revision!(source.graph_revision_id)
      target = insert_service(graph, "target")
      graph = Graphs.load_revision!(target.graph_revision_id)
      segment = Enum.find(Graph.nodes(graph), &(&1.type == NetworkSegment))
      other_segment = insert_segment(graph, "other")
      graph = Graphs.load_revision!(other_segment.graph_revision_id)
      [contains, runs] = Graph.edges(graph)
      reachability_id = Ecto.UUID.generate()

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "save_graph", %{
        "graph" => %{
          "id" => graph.id,
          "revision_id" => graph.revision_id,
          "title" => "saved graph",
          "nodes" => [
            %{
              "id" => segment.id,
              "type" => "NetworkSegment",
              "data" => NetworkDefense.Graph.Data.to_params(segment.data),
              "view_data" => %{"x_pos" => 0, "y_pos" => 0}
            },
            %{
              "id" => other_segment.id,
              "type" => "NetworkSegment",
              "data" => NetworkDefense.Graph.Data.to_params(other_segment.data),
              "view_data" => %{"x_pos" => 0, "y_pos" => 0}
            },
            %{
              "id" => source.id,
              "type" => "Host",
              "data" => NetworkDefense.Graph.Data.to_params(source.data),
              "view_data" => %{"x_pos" => 120, "y_pos" => 240}
            },
            %{
              "id" => target.id,
              "type" => "Service",
              "data" => NetworkDefense.Graph.Data.to_params(target.data),
              "view_data" => %{"x_pos" => 360, "y_pos" => 480}
            }
          ],
          "edges" => [
            %{
              "id" => contains.id,
              "from_id" => segment.id,
              "to_id" => source.id,
              "type" => "Contains",
              "data" => %{}
            },
            %{
              "id" => runs.id,
              "from_id" => source.id,
              "to_id" => target.id,
              "type" => "Runs",
              "data" => %{}
            },
            %{
              "id" => reachability_id,
              "from_id" => segment.id,
              "to_id" => other_segment.id,
              "type" => "SegmentReachability",
              "data" => %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
            }
          ]
        }
      })

      assert_reply(view, %{
        status: "ok",
        graph: %{title: "saved graph", edges: wire_edges}
      })

      assert Enum.map(wire_edges, & &1.type) |> Enum.sort() ==
               Enum.sort(["Contains", "Runs", "SegmentReachability"])

      refute Enum.any?(wire_edges, &(&1.type == "NetworkReachability"))

      saved_graph = latest_graph(graph.id)

      assert saved_graph.title == "saved graph"
      assert saved_graph.revision_id != graph.revision_id

      saved_edges = Graph.edges(saved_graph)
      refute Enum.any?(saved_edges, &(&1.type == NetworkReachability))

      assert Enum.find(saved_edges, &(&1.type == Contains)).from_id == segment.id
      assert Enum.find(saved_edges, &(&1.type == Contains)).to_id == source.id
      assert Enum.find(saved_edges, &(&1.type == Runs)).from_id == source.id
      assert Enum.find(saved_edges, &(&1.type == Runs)).to_id == target.id

      assert %{from_id: from_segment_id, to_id: to_segment_id, type: SegmentReachability} =
               Enum.find(saved_edges, &(&1.type == SegmentReachability))

      assert from_segment_id == segment.id
      assert to_segment_id == other_segment.id

      source_node = Enum.find(saved_graph.nodes, &(&1.id == source.id))
      target_node = Enum.find(saved_graph.nodes, &(&1.id == target.id))
      assert source_node.view_data.x_pos == 120.0
      assert source_node.view_data.y_pos == 240.0
      assert target_node.view_data.x_pos == 360.0
      assert target_node.view_data.y_pos == 480.0
    end

    test "rejects a save payload with an operational NetworkReachability edge", %{conn: conn} do
      graph = insert_graph("rejected-save")
      source = insert_node(graph, "source")
      graph = Graphs.load_revision!(source.graph_revision_id)

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "save_graph", %{
        "graph" => %{
          "id" => graph.id,
          "revision_id" => graph.revision_id,
          "title" => "rejected graph",
          "nodes" => [
            %{
              "id" => source.id,
              "type" => "Host",
              "data" => NetworkDefense.Graph.Data.to_params(source.data),
              "view_data" => %{"x_pos" => 0, "y_pos" => 0}
            }
          ],
          "edges" => [
            %{
              "id" => Ecto.UUID.generate(),
              "from_id" => source.id,
              "to_id" => Ecto.UUID.generate(),
              "type" => "NetworkReachability",
              "data" => %{"protocol" => "any"}
            }
          ]
        }
      })

      assert_reply(view, %{status: "invalid_graph", graph: nil})

      assert latest_graph(graph.id).revision_id == graph.revision_id
    end

    test "replaces a selected graph revision", %{conn: conn} do
      graph = insert_graph("stale-graph")

      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "save_graph", %{
        "graph" => %{
          "id" => graph.id,
          "revision_id" => graph.revision_id,
          "title" => "stale graph",
          "nodes" => [],
          "edges" => []
        }
      })

      assert latest_graph(graph.id).title == "stale graph"
    end
  end

  defp insert_graph(title) do
    assert {:ok, graph} = Graphs.insert(Graph.new(title))
    graph
  end

  defp insert_running_experiment(graph_revision_id) do
    insert_experiment(graph_revision_id, "running", 0)
  end

  defp insert_completed_experiment(graph_revision_id) do
    insert_experiment(graph_revision_id, "completed", 10)
  end

  defp insert_failed_experiment(graph_revision_id) do
    insert_experiment(graph_revision_id, "failed", 0)
  end

  defp insert_experiment(graph_revision_id, status, completed_trials) do
    experiment =
      NetworkDefense.Simulation.Experiment.new(
        graph_revision_id: graph_revision_id,
        master_seed: 1,
        iteration_count: 1,
        max_attempts: 1,
        total_trials: 10,
        completed_trials: completed_trials,
        status: status
      )

    assert {:ok, experiment} = Experiments.create(experiment)
    experiment.id
  end

  defp insert_running_optimization(graph_revision_id) do
    %NetworkDefense.Optimization.OptimizationRun{}
    |> NetworkDefense.Optimization.OptimizationRun.changeset(%{
      graph_revision_id: graph_revision_id,
      strategy: "cvss",
      requested_budget: 1,
      status: "running"
    })
    |> Repo.insert!()
    |> Map.fetch!(:id)
  end

  defp insert_running_evaluation do
    manifest =
      %NetworkDefense.Evaluation.EvaluationManifest{}
      |> NetworkDefense.Evaluation.EvaluationManifest.changeset(%{
        manifest_id: "manifest-#{System.unique_integer([:positive])}",
        title: "evaluation-title",
        content: %{}
      })
      |> Repo.insert!()

    graph = insert_graph("evaluation-graph")

    %NetworkDefense.Evaluation.EvaluationRun{}
    |> NetworkDefense.Evaluation.EvaluationRun.changeset(%{
      evaluation_manifest_id: manifest.id,
      source_graph_revision_id: graph.revision_id,
      resolved_manifest: %{},
      status: "running"
    })
    |> Repo.insert!()
    |> Map.fetch!(:id)
  end

  defp assert_strategy_optimization(conn, strategy, _strategy_name) do
    graph = insert_graph("#{strategy}-test")
    foothold = insert_node(graph, "entry-host")
    graph = Graphs.load_revision!(foothold.graph_revision_id)
    correlation_id = "#{strategy}-request"

    {:ok, view, _html} = live(conn, ~p"/")
    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Optimizations.optimization_events_topic())

    render_hook(view, "run_optimization_request", %{
      "request" => %{
        "graph_revision_id" => graph.revision_id,
        "correlation_id" => correlation_id,
        "optimization_params" => %{
          "strategy" => strategy,
          "budget" => 1,
          "simulation_params" => %{
            "monte_carlo_trials" => 1,
            "iterations_per_run" => 1,
            "initial_foothold_node_id" => foothold.id,
            "generate_seed" => true,
            "max_attempts" => 1
          }
        }
      }
    })

    assert_reply(view, %{status: "accepted", correlation_id: ^correlation_id})

    perform_optimization_job()

    assert_receive {:optimization_completed,
                    %{
                      correlation_id: ^correlation_id,
                      graph_revision_id: optimized_revision_id
                    }},
                   5_000

    expected_title = "#{strategy}-test"
    assert %{title: ^expected_title} = Graphs.load_revision(optimized_revision_id)
  end

  defp insert_node(graph, name) do
    segment =
      Node.new(graph.id, %{
        type: Atom.to_string(NetworkSegment),
        data: %{"name" => "segment"},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    node =
      Node.new(graph.id, %{
        type: Atom.to_string(Host),
        data: %{"name" => name},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    graph.revision_id
    |> Graphs.load_revision!()
    |> Graph.add_node(segment)
    |> Graph.add_node(node)
    |> Graph.add_edge(
      Edge.new(graph.id, segment.id, node.id, %{type: Atom.to_string(Contains), data: %{}})
    )
    |> append_revision()
    |> Graph.node(node.id)
  end

  defp insert_service(graph, name) do
    node =
      Node.new(graph.id, %{
        type: Atom.to_string(Service),
        data: %{"name" => name, "protocol" => "tcp", "port" => 443},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    host = Enum.find(Graph.nodes(graph), &(&1.type == Host))

    graph.revision_id
    |> Graphs.load_revision!()
    |> Graph.add_node(node)
    |> Graph.add_edge(
      Edge.new(graph.id, host.id, node.id, %{type: Atom.to_string(Runs), data: %{}})
    )
    |> append_revision()
    |> Graph.node(node.id)
  end

  defp insert_segment(graph, name) do
    node =
      Node.new(graph.id, %{
        type: Atom.to_string(NetworkSegment),
        data: %{"name" => name},
        view_data: %{"x_pos" => 0, "y_pos" => 0}
      })

    graph.revision_id
    |> Graphs.load_revision!()
    |> Graph.add_node(node)
    |> append_revision()
    |> Graph.node(node.id)
  end

  defp append_revision(graph) do
    assert {:ok, graph} = Graphs.append_optimization(graph)
    graph
  end

  defp latest_graph(graph_id) do
    graph_id
    |> then(fn id ->
      Graphs.list_summaries() |> Enum.filter(&(&1.graphId == id)) |> List.last()
    end)
    |> then(&Graphs.load_revision!(&1.revisionId))
  end

  defp perform_simulation_job do
    assert [%{args: %{"experiment_id" => experiment_id, "correlation_id" => correlation_id}}] =
             all_enqueued(worker: SimulationWorker)

    assert :ok =
             perform_job(SimulationWorker, %{
               "experiment_id" => experiment_id,
               "correlation_id" => correlation_id
             })

    {experiment_id, correlation_id}
  end

  defp perform_optimization_job do
    assert [%{args: %{"run_id" => run_id, "request" => request_params}}] =
             all_enqueued(worker: OptimizationWorker)

    assert :ok =
             perform_job(OptimizationWorker, %{
               "run_id" => run_id,
               "request" => request_params
             })

    run_id
  end

  defp perform_evaluation_job do
    assert [%{args: %{"run_id" => run_id}}] = all_enqueued(worker: EvaluationWorker)
    assert :ok = perform_job(EvaluationWorker, %{"run_id" => run_id})
    run_id
  end
end
