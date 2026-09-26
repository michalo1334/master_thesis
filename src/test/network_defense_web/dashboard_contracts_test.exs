defmodule NetworkDefenseWeb.DashboardContractsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.Registry
  alias NetworkDefense.Contracts
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Contracts.SaveGraphContract
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Graph.TopologyProjection, as: DomainTopologyProjection
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.NetworkSegment
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    Contains,
    HasVulnerability,
    Runs,
    SegmentReachability,
    StoresCredential
  }

  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest

  alias NetworkDefenseWeb.Contracts.Dashboard.ExecutionProgressEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.DescribeManifestReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchSimulationReportReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationReportCapabilityStatus

  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.OpenGraphReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.ProjectTopologyDraftPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.ProjectTopologyDraftReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.SaveGraphPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.SaveGraphReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection
  alias NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.Anchor
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationReportPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationReportReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationRunsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationCompletedEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.FetchRunsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.FetchRunsReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.DocumentCatalogItem
  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.FetchDocumentCatalogPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Workspace.FetchDocumentCatalogReply

  import NetworkDefense.GraphFixtures, only: [edge: 4, edge: 5, graph: 3, node: 4]

  @graph_id "00000000-0000-0000-0000-000000000001"
  @parent_graph_id "00000000-0000-0000-0000-000000000011"
  @host_id "00000000-0000-0000-0000-000000000002"
  @service_id "00000000-0000-0000-0000-000000000003"
  @vulnerability_id "00000000-0000-0000-0000-000000000004"
  @credential_id "00000000-0000-0000-0000-000000000005"
  @runs_edge_id "00000000-0000-0000-0000-000000000006"
  @reachability_edge_id "00000000-0000-0000-0000-000000000007"
  @vulnerability_edge_id "00000000-0000-0000-0000-000000000008"
  @stores_edge_id "00000000-0000-0000-0000-000000000009"
  @auth_edge_id "00000000-0000-0000-0000-000000000010"
  @segment_id "00000000-0000-0000-0000-000000000012"
  @segment_b_id "00000000-0000-0000-0000-000000000013"
  @contains_edge_id "00000000-0000-0000-0000-000000000014"

  # Projection transport fixture: deterministic UUIDs so array order is predictable.
  @projection_graph_id "00000000-0000-0000-0000-000000000101"
  @projection_segment_id "00000000-0000-0000-0000-000000000102"
  @projection_segment_b_id "00000000-0000-0000-0000-000000000103"
  @projection_host_id "00000000-0000-0000-0000-000000000104"
  @projection_host_b_id "00000000-0000-0000-0000-000000000105"
  @projection_service_id "00000000-0000-0000-0000-000000000106"
  @projection_service_b_id "00000000-0000-0000-0000-000000000107"
  @projection_vulnerability_id "00000000-0000-0000-0000-000000000108"
  @projection_contains_edge_id "00000000-0000-0000-0000-000000000109"
  @projection_contains_edge_b_id "00000000-0000-0000-0000-000000000110"
  @projection_runs_edge_id "00000000-0000-0000-0000-000000000111"
  @projection_runs_edge_b_id "00000000-0000-0000-0000-000000000112"
  @projection_reachability_edge_id "00000000-0000-0000-0000-000000000113"
  @projection_self_policy_edge_id "00000000-0000-0000-0000-000000000114"
  @projection_vulnerability_edge_id "00000000-0000-0000-0000-000000000115"
  test "all dashboard contracts are embedded schemas with changesets" do
    Registry.list_contract_modules(:all)
    |> Enum.each(fn contract ->
      assert contract.__schema__(:source) == nil
      assert function_exported?(contract, :changeset, 2)
    end)
  end

  test "casts a graph payload and converts it back to domain attributes" do
    attrs = %{
      "graph" => %{
        "id" => @graph_id,
        "revision_id" => @parent_graph_id,
        "title" => "Test graph",
        "lock_version" => 1,
        "nodes" => [
          %{
            "id" => @host_id,
            "type" => "Host",
            "data" => %{"name" => "internet"},
            "view_data" => %{"x_pos" => 120, "y_pos" => 240}
          }
        ],
        "edges" => []
      }
    }

    assert {:ok, payload} = SaveGraphPayload.validate(attrs)
    assert %{name: "internet"} = payload.graph.nodes |> hd() |> Map.fetch!(:data)

    assert %{
             "title" => "Test graph",
             "revision_id" => @parent_graph_id,
             "nodes" => [
               %{
                 "id" => @host_id,
                 "type" => "Host",
                 "data" => %{"name" => "internet"},
                 "view_data" => %{"x_pos" => 120.0, "y_pos" => 240.0, "radius" => nil}
               }
             ],
             "edges" => []
           } = Contracts.to_params(payload.graph)
  end

  test "rejects invalid polymorphic node data" do
    attrs = %{
      "graph" => %{
        "id" => @graph_id,
        "revision_id" => @parent_graph_id,
        "title" => "Test graph",
        "lock_version" => 1,
        "nodes" => [
          %{
            "id" => @host_id,
            "type" => "Service",
            "data" => %{"name" => "dns", "protocol" => "icmp", "port" => 53},
            "view_data" => %{"x_pos" => 0, "y_pos" => 0}
          }
        ],
        "edges" => []
      }
    }

    assert {:error, changeset} = SaveGraphPayload.validate(attrs)
    assert %{graph: %{nodes: [%{data: ["is invalid"]}]}} = errors_on(changeset)
  end

  test "requires positive simulation parameters" do
    attrs = %{
      "graph_revision_id" => "graph-1",
      "correlation_id" => "request-1",
      "simulation_params" => %{"monte_carlo_trials" => 0, "iterations_per_run" => 1}
    }

    assert {:error, changeset} = RunSimulationRequest.validate(attrs)

    assert %{simulation_params: %{monte_carlo_trials: ["must be greater than 0"]}} =
             errors_on(changeset)
  end

  test "validates optional document catalog manifest identity" do
    attrs = %{
      "id" => @graph_id,
      "kind" => "analysis_report",
      "graph_id" => @graph_id,
      "graph_revision_id" => @parent_graph_id,
      "graph_title" => "Source graph",
      "revision_kind" => "initial",
      "revision_number" => 1,
      "created_at" => "2026-01-01T00:00:00Z",
      "manifest_id" => "manifest-1",
      "manifest_title" => "Analysis"
    }

    assert {:ok, %DocumentCatalogItem{manifest_id: "manifest-1", manifest_title: "Analysis"}} =
             DocumentCatalogItem.validate(attrs)

    assert {:error, changeset} =
             DocumentCatalogItem.validate(%{
               attrs
               | "manifest_title" => String.duplicate("x", 256)
             })

    assert %{manifest_title: ["should be at most 255 character(s)"]} = errors_on(changeset)
  end

  test "rejects oversized asynchronous operation correlation IDs" do
    correlation_id = String.duplicate("c", 129)

    assert {:error, simulation_changeset} =
             RunSimulationRequest.validate(%{
               "graph_revision_id" => Ecto.UUID.generate(),
               "correlation_id" => correlation_id,
               "simulation_params" => %{
                 "monte_carlo_trials" => 1,
                 "iterations_per_run" => 1,
                 "initial_foothold_node_id" => Ecto.UUID.generate()
               }
             })

    assert %{correlation_id: [_ | _]} = errors_on(simulation_changeset)

    assert {:error, optimization_changeset} =
             RunOptimizationRequest.validate(%{
               "graph_revision_id" => Ecto.UUID.generate(),
               "correlation_id" => correlation_id,
               "optimization_params" => %{"strategy" => "cvss", "budget" => 1}
             })

    assert %{correlation_id: [_ | _]} = errors_on(optimization_changeset)
  end

  test "maps validated graph contracts to canonical graph replacement attributes" do
    attrs = %{
      "id" => @graph_id,
      "revision_id" => @parent_graph_id,
      "title" => "Test graph",
      "lock_version" => 1,
      "nodes" => [
        %{
          "id" => @host_id,
          "type" => "Host",
          "data" => %{"name" => "internet"},
          "view_data" => %{"x_pos" => 120, "y_pos" => 240}
        }
      ],
      "edges" => []
    }

    assert {:ok,
            %{
              attrs: %{
                "title" => "Test graph",
                "nodes" => [
                  %{
                    "id" => @host_id,
                    "type" => type,
                    "data" => %{"name" => "internet"},
                    "view_data" => %{"x_pos" => 120.0, "y_pos" => 240.0}
                  }
                ],
                "edges" => []
              }
            }} =
             with(
               {:ok, graph} <- SaveGraphContract.validate(attrs),
               do: SaveGraphContract.to_replace_attrs(graph)
             )

    assert type == Atom.to_string(Host)
  end

  test "rejects persisted type names at the wire boundary" do
    for type <- [Atom.to_string(Host), "ok"] do
      assert {:error, changeset} =
               GraphContract.validate(%{
                 "id" => @graph_id,
                 "title" => "Test graph",
                 "lock_version" => 1,
                 "nodes" => [
                   %{
                     "id" => @host_id,
                     "type" => type,
                     "data" => %{"name" => "internet"},
                     "view_data" => %{"x_pos" => 0, "y_pos" => 0}
                   }
                 ],
                 "edges" => []
               })

      assert %{nodes: [%{type: ["is invalid"]}]} = errors_on(changeset)
    end
  end

  test "round trips every graph variant between the domain and wire contracts" do
    graph = Graph.new("Test graph")

    nodes = [
      %Node{
        id: @segment_id,
        graph_id: graph.id,
        type: Atom.to_string(NetworkSegment),
        data: %{"name" => "dmz"},
        view_data: %{"x_pos" => 10, "y_pos" => 10}
      },
      %Node{
        id: @segment_b_id,
        graph_id: graph.id,
        type: Atom.to_string(NetworkSegment),
        data: %{"name" => "internal"},
        view_data: %{"x_pos" => 20, "y_pos" => 10}
      },
      %Node{
        id: @host_id,
        graph_id: graph.id,
        type: Atom.to_string(Host),
        data: %{"name" => "internet"},
        view_data: %{"x_pos" => 10, "y_pos" => 20, "radius" => 30}
      },
      %Node{
        id: @service_id,
        graph_id: graph.id,
        type: Atom.to_string(Service),
        data: %{"name" => "dns", "protocol" => "udp", "port" => 53},
        view_data: %{"x_pos" => 40, "y_pos" => 50}
      },
      %Node{
        id: @vulnerability_id,
        graph_id: graph.id,
        type: Atom.to_string(Vulnerability),
        data: %{
          "identifier" => "CVE-2026-0001",
          "cvss" => cvss(),
          "exploit_probability" => 0.4
        },
        view_data: %{"x_pos" => 70, "y_pos" => 80}
      },
      %Node{
        id: @credential_id,
        graph_id: graph.id,
        type: Atom.to_string(Credential),
        data: %{"identifier" => "key-1", "credential_type" => "ssh_key"},
        view_data: %{"x_pos" => 100, "y_pos" => 110}
      }
    ]

    edges = [
      %Edge{
        id: @contains_edge_id,
        graph_id: graph.id,
        from_id: @segment_id,
        to_id: @host_id,
        type: Atom.to_string(Contains),
        data: %{}
      },
      %Edge{
        id: @runs_edge_id,
        graph_id: graph.id,
        from_id: @host_id,
        to_id: @service_id,
        type: Atom.to_string(Runs),
        data: %{}
      },
      %Edge{
        id: @reachability_edge_id,
        graph_id: graph.id,
        from_id: @segment_b_id,
        to_id: @segment_id,
        type: Atom.to_string(SegmentReachability),
        data: %{"protocol" => "tcp", "port_start" => 443, "port_end" => 443}
      },
      %Edge{
        id: @vulnerability_edge_id,
        graph_id: graph.id,
        from_id: @service_id,
        to_id: @vulnerability_id,
        type: Atom.to_string(HasVulnerability),
        data: %{"required_privilege" => "none", "granted_privilege" => "user"}
      },
      %Edge{
        id: @stores_edge_id,
        graph_id: graph.id,
        from_id: @host_id,
        to_id: @credential_id,
        type: Atom.to_string(StoresCredential),
        data: %{"required_privilege" => "user"}
      },
      %Edge{
        id: @auth_edge_id,
        graph_id: graph.id,
        from_id: @credential_id,
        to_id: @service_id,
        type: Atom.to_string(AuthenticatesTo),
        data: %{"granted_privilege" => "administrator"}
      }
    ]

    assert {:ok, graph} = Graph.hydrate(graph, nodes, edges)

    assert {:ok, wire} = GraphContract.from_domain(graph)

    assert wire.parent_revision_id == nil
    assert wire.revision_kind == "initial"

    assert [
             "Credential",
             "Host",
             "NetworkSegment",
             "NetworkSegment",
             "Service",
             "Vulnerability"
           ] =
             wire
             |> Map.fetch!(:nodes)
             |> Enum.map(&Map.fetch!(&1, :type))
             |> Enum.sort()

    assert [
             "AuthenticatesTo",
             "Contains",
             "HasVulnerability",
             "Runs",
             "SegmentReachability",
             "StoresCredential"
           ] =
             wire
             |> Map.fetch!(:edges)
             |> Enum.map(&Map.fetch!(&1, :type))
             |> Enum.sort()

    refute Enum.any?(wire.edges, &(&1.type == "NetworkReachability"))

    assert %{radius: 30.0} =
             wire
             |> Map.fetch!(:nodes)
             |> Enum.find(&(Map.fetch!(&1, :id) == @host_id))
             |> Map.fetch!(:view_data)
  end

  test "preserves revision lineage through an open graph reply" do
    graph =
      Graph.new("Child graph")
      |> Map.put(:revision_id, @graph_id)
      |> Map.put(:parent_revision_id, @parent_graph_id)
      |> Map.put(:revision_number, 2)
      |> Map.put(:revision_kind, :optimization)

    assert {:ok, wire_graph} = GraphContract.from_domain(graph)
    assert {:ok, reply} = OpenGraphReply.validate(%{status: "ok", graph: wire_graph})

    assert %{
             graph: %{
               parent_revision_id: @parent_graph_id,
               revision_kind: "optimization",
               revision_number: 2
             }
           } = OpenGraphReply.to_wire(reply)
  end

  test "requires an optimization id on the completed event" do
    assert {:ok, %OptimizationCompletedEvent{optimization_id: "optimization-1"}} =
             OptimizationCompletedEvent.validate(%{
               correlation_id: "request-1",
               graph_id: "graph-1",
               graph_revision_id: "revision-1",
               output_graph_revision_id: "output-revision-1",
               optimization_id: "optimization-1"
             })

    assert {:error, changeset} =
             OptimizationCompletedEvent.validate(%{
               correlation_id: "request-1",
               graph_id: "graph-1",
               graph_revision_id: "revision-1",
               output_graph_revision_id: "output-revision-1"
             })

    assert %{optimization_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "validates execution progress events" do
    base = %{correlation_id: "request-1", graph_id: "graph-1", graph_revision_id: "revision-1"}

    assert {:ok, %ExecutionProgressEvent{completed: 1, total: 2, detail: "Scoring defenses"}} =
             ExecutionProgressEvent.validate(
               Map.merge(base, %{completed: 1, total: 2, detail: "Scoring defenses"})
             )

    assert {:ok, %ExecutionProgressEvent{completed: 1, total: 2, detail: nil}} =
             ExecutionProgressEvent.validate(Map.merge(base, %{completed: 1, total: 2}))

    for {attrs, field, message} <- [
          {%{total: 2}, :completed, "can't be blank"},
          {%{completed: -1, total: 2}, :completed, "must be greater than or equal to 0"},
          {%{completed: 1, total: 0}, :total, "must be greater than 0"}
        ] do
      assert {:error, changeset} = ExecutionProgressEvent.validate(Map.merge(base, attrs))

      assert %{^field => [^message]} = errors_on(changeset)
    end
  end

  test "requires optimization report fetch identifiers to be UUIDs" do
    assert {:error, changeset} =
             FetchOptimizationReportPayload.validate(%{
               "document_id" => @graph_id,
               "optimization_id" => "not-a-uuid"
             })

    assert %{optimization_id: ["is invalid"]} = errors_on(changeset)
  end

  test "rejects non-UUID graph revision ids in optimization run fetch" do
    assert {:error, changeset} =
             FetchOptimizationRunsPayload.validate(%{"graph_revision_ids" => ["not-a-uuid"]})

    assert %{graph_revision_ids: ["contains an invalid UUID"]} = errors_on(changeset)
  end

  test "accepts an empty fetch runs payload" do
    assert {:ok, %FetchRunsPayload{}} = FetchRunsPayload.validate(%{})
  end

  test "round trips document catalog relation fields" do
    assert {:ok, payload} =
             FetchDocumentCatalogPayload.validate(%{
               "related_graph_ids" => [@graph_id]
             })

    assert payload.related_graph_ids == [@graph_id]

    item = %{
      "id" => @graph_id,
      "kind" => "graph",
      "graph_id" => @graph_id,
      "graph_revision_id" => @graph_id,
      "parent_revision_id" => @parent_graph_id,
      "graph_title" => "Graph",
      "revision_kind" => "initial",
      "revision_number" => 1,
      "created_at" => "2026-01-01T00:00:00Z"
    }

    assert {:ok, reply} =
             FetchDocumentCatalogReply.validate(%{
               "items" => [item],
               "related_items" => [item],
               "filter_options" => %{}
             })

    assert [%{parent_revision_id: @parent_graph_id}] = reply.related_items
  end

  test "round trips a fetch runs reply with run summaries" do
    attrs = %{
      "runs" => [
        %{
          "id" => @graph_id,
          "kind" => "simulation",
          "title" => "Test graph",
          "status" => "running",
          "completed" => 2,
          "total" => 10,
          "started_at" => "2026-01-01T00:00:00Z"
        }
      ]
    }

    assert {:ok, reply} = FetchRunsReply.validate(attrs)

    assert %{
             runs: [
               %{
                 id: @graph_id,
                 kind: "simulation",
                 title: "Test graph",
                 status: "running",
                 completed: 2,
                 total: 10,
                 started_at: "2026-01-01T00:00:00Z"
               }
             ]
           } = FetchRunsReply.to_wire(reply)
  end

  test "rejects a run summary without required fields" do
    assert {:error, changeset} = FetchRunsReply.validate(%{"runs" => [%{"title" => "x"}]})

    assert %{
             runs: [
               %{id: ["can't be blank"], kind: ["can't be blank"], status: ["can't be blank"]}
             ]
           } =
             errors_on(changeset)
  end

  test "round trips a describe manifest reply with plans and comparison groups" do
    attrs = %{
      "status" => "ok",
      "plans" => [
        %{
          "model_variant" => "full",
          "strategy" => "cvss",
          "budget" => 1,
          "selection_seed" => 101
        }
      ],
      "comparison_groups" => [
        %{
          "index" => 0,
          "tested" => %{
            "model_variant" => "full",
            "strategy" => "cvss",
            "budget" => 1,
            "selection_seeds" => [101]
          },
          "baseline" => %{
            "model_variant" => "full",
            "strategy" => "null",
            "budget" => 1,
            "selection_seeds" => [102]
          },
          "outcome" => "blast_radius"
        }
      ],
      "errors" => []
    }

    assert {:ok, reply} = DescribeManifestReply.validate(attrs)

    assert %{
             status: "ok",
             plans: [%{model_variant: "full", strategy: "cvss", selection_seed: 101}],
             comparison_groups: [
               %{
                 index: 0,
                 tested: %{strategy: "cvss", selection_seeds: [101]},
                 baseline: %{strategy: "null", selection_seeds: [102]},
                 outcome: "blast_radius"
               }
             ]
           } = DescribeManifestReply.to_wire(reply)
  end

  test "rejects a describe manifest plan with an unknown model variant" do
    assert {:error, changeset} =
             DescribeManifestReply.validate(%{
               "status" => "ok",
               "plans" => [
                 %{
                   "model_variant" => "bogus",
                   "strategy" => "cvss",
                   "budget" => 1,
                   "selection_seed" => 101
                 }
               ],
               "errors" => []
             })

    assert %{plans: [%{model_variant: ["is invalid"]}]} = errors_on(changeset)
  end

  test "maps a persisted optimization run report to the web contract" do
    run = %OptimizationRun{id: @graph_id, graph_revision_id: @parent_graph_id}
    graph = %{Graph.new("Test graph") | id: @graph_id, revision_id: @parent_graph_id}

    report = %{
      strategy: "cvss",
      requested_budget: 2,
      used_budget: 1,
      runtime_ms: 12,
      actions: [
        %{
          id: "target-1",
          label: "Patch CVE-1",
          kind: "Vulnerability patch",
          cvss_score: 7.5,
          cost: 1
        }
      ]
    }

    report = %NetworkDefense.Optimization.OptimizationReport{
      optimization_id: run.id,
      graph_id: graph.id,
      graph_title: graph.title,
      graph: graph,
      graph_revision_id: run.graph_revision_id,
      strategy: report.strategy,
      requested_budget: report.requested_budget,
      used_budget: report.used_budget,
      runtime_ms: report.runtime_ms,
      actions: report.actions
    }

    assert {:ok, reply} = FetchOptimizationReportReply.from_domain(report)

    assert %{
             optimization_id: @graph_id,
             graph_id: @graph_id,
             graph_title: "Test graph",
             graph_revision_id: @parent_graph_id,
             report: %{
               strategy: "cvss",
               used_budget: 1,
               actions: [%{id: "target-1", label: "Patch CVE-1", cvss_score: 7.5, cost: 1}]
             }
           } = FetchOptimizationReportReply.to_wire(reply)
  end

  # Projection ID arrays are sorted normalized references to root records, not owned embeds.
  test "converts a domain topology projection into wire contracts with contract type names" do
    assert %{
             segments: segments,
             hosts: hosts,
             services: services,
             attachments: attachments,
             policy_groups: policy_groups,
             flow_groups: flow_groups,
             issues: []
           } = projection_wire()

    assert segments == [
             %{
               id: @projection_segment_id,
               host_ids: [@projection_host_id],
               host_count: 1,
               service_count: 1,
               context_count: 1
             },
             %{
               id: @projection_segment_b_id,
               host_ids: [@projection_host_b_id],
               host_count: 1,
               service_count: 1,
               context_count: 0
             }
           ]

    assert hosts == [
             %{
               id: @projection_host_id,
               segment_id: @projection_segment_id,
               service_ids: [@projection_service_id],
               service_count: 1,
               context_count: 1
             },
             %{
               id: @projection_host_b_id,
               segment_id: @projection_segment_b_id,
               service_ids: [@projection_service_b_id],
               service_count: 1,
               context_count: 0
             }
           ]

    assert services == [
             %{id: @projection_service_id, host_id: @projection_host_id},
             %{id: @projection_service_b_id, host_id: @projection_host_b_id}
           ]

    assert attachments == [
             %{
               id: @projection_vulnerability_id,
               node_type: "Vulnerability",
               anchors: [
                 %{
                   node_id: @projection_host_id,
                   edge_id: @projection_vulnerability_edge_id,
                   relationship_type: "HasVulnerability"
                 }
               ]
             }
           ]

    assert policy_groups == [
             %{
               from_segment_id: @projection_segment_id,
               to_segment_id: @projection_segment_b_id,
               edge_ids: [@projection_reachability_edge_id]
             },
             %{
               from_segment_id: @projection_segment_b_id,
               to_segment_id: @projection_segment_b_id,
               edge_ids: [@projection_self_policy_edge_id]
             }
           ]

    assert [
             %{
               source_host_id: @projection_host_id,
               target_host_id: @projection_host_b_id,
               service_ids: [@projection_service_b_id],
               flow_ids: [flow_id]
             },
             %{
               source_host_id: @projection_host_b_id,
               target_host_id: @projection_host_b_id,
               service_ids: [@projection_service_b_id],
               flow_ids: [self_flow_id]
             }
           ] = flow_groups

    assert {:ok, _uuid} = Ecto.UUID.cast(flow_id)
    assert {:ok, _uuid} = Ecto.UUID.cast(self_flow_id)
  end

  test "rejects a projection with unknown enum values and negative counts" do
    assert {:error, changeset} =
             TopologyProjection.validate(%{
               "segments" => [
                 %{
                   "id" => @segment_id,
                   "host_count" => -1,
                   "service_count" => 0,
                   "context_count" => 0
                 }
               ]
             })

    assert %{segments: [%{host_count: ["must be greater than or equal to 0"]}]} =
             errors_on(changeset)

    assert {:error, changeset} =
             TopologyProjection.validate(%{
               "attachments" => [
                 %{
                   "id" => @vulnerability_id,
                   "node_type" => "NetworkSegment",
                   "anchors" => [
                     %{
                       "node_id" => @host_id,
                       "edge_id" => @vulnerability_edge_id,
                       "relationship_type" => "Runs"
                     }
                   ]
                 }
               ]
             })

    assert %{
             attachments: [
               %{
                 node_type: ["is invalid"],
                 anchors: [%{relationship_type: ["is invalid"]}]
               }
             ]
           } = errors_on(changeset)

    assert {:ok, %Anchor{relationship_type: "AuthenticatesTo"}} =
             Anchor.validate(%{
               "node_id" => @host_id,
               "edge_id" => @auth_edge_id,
               "relationship_type" => "AuthenticatesTo"
             })
  end

  test "round trips a draft topology payload and reply" do
    assert {:ok, payload} =
             ProjectTopologyDraftPayload.validate(%{
               "document_id" => @graph_id,
               "semantic_version" => 3,
               "graph" => %{
                 "id" => @graph_id,
                 "title" => "draft",
                 "nodes" => [],
                 "edges" => []
               }
             })

    assert payload.document_id == @graph_id
    assert payload.semantic_version == 3
    assert payload.graph.id == @graph_id

    assert {:ok, reply} =
             ProjectTopologyDraftReply.validate(%{
               "status" => "ok",
               "document_id" => @graph_id,
               "semantic_version" => 3,
               "topology_projection" => projection_wire(),
               "errors" => []
             })

    assert %{
             status: "ok",
             document_id: @graph_id,
             semantic_version: 3,
             errors: [],
             topology_projection: %{segments: [%{id: @projection_segment_id} | _]}
           } = ProjectTopologyDraftReply.to_wire(reply)

    assert {:ok, error_reply} =
             ProjectTopologyDraftReply.validate(%{
               "status" => "invalid_graph",
               "errors" => [
                 %{
                   "entity_kind" => "graph",
                   "field_path" => ["edges"],
                   "message" => "invalid_endpoints"
                 }
               ]
             })

    assert error_reply.topology_projection == nil
    assert error_reply.document_id == nil
  end

  test "rejects a draft payload without an identity, graph, or non-negative version" do
    assert {:error, changeset} =
             ProjectTopologyDraftPayload.validate(%{
               "semantic_version" => 0,
               "graph" => %{
                 "id" => @graph_id,
                 "title" => "draft",
                 "nodes" => [],
                 "edges" => []
               }
             })

    assert %{document_id: ["can't be blank"]} = errors_on(changeset)

    assert {:error, changeset} =
             ProjectTopologyDraftPayload.validate(%{
               "document_id" => @graph_id,
               "semantic_version" => -1
             })

    assert %{graph: ["can't be blank"]} = errors_on(changeset)

    assert {:error, changeset} =
             ProjectTopologyDraftPayload.validate(%{
               "document_id" => "not-a-uuid",
               "semantic_version" => 0,
               "graph" => %{
                 "id" => @graph_id,
                 "title" => "draft",
                 "nodes" => [],
                 "edges" => []
               }
             })

    assert %{document_id: ["is invalid"]} = errors_on(changeset)

    assert {:error, changeset} = ProjectTopologyDraftReply.validate(%{"status" => "not_found"})
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "bundles a matching topology projection into open and save replies" do
    wire_projection = projection_wire()

    assert {:ok, reply} =
             OpenGraphReply.validate(%{
               "status" => "ok",
               "graph" => %{
                 "id" => @graph_id,
                 "title" => "open",
                 "nodes" => [],
                 "edges" => []
               },
               "topology_projection" => wire_projection
             })

    assert %{topology_projection: %{segments: [%{id: @projection_segment_id} | _]}} =
             OpenGraphReply.to_wire(reply)

    assert {:ok, save_reply} =
             SaveGraphReply.validate(%{
               "status" => "ok",
               "graph" => %{
                 "id" => @graph_id,
                 "title" => "save",
                 "nodes" => [],
                 "edges" => []
               },
               "topology_projection" => wire_projection,
               "errors" => []
             })

    assert %{status: "ok", topology_projection: %{hosts: [_ | _]}} =
             SaveGraphReply.to_wire(save_reply)

    assert {:ok, error_reply} = OpenGraphReply.validate(%{"status" => "not_found"})
    assert error_reply.topology_projection == nil
  end

  test "requires capability status counts and minimum support" do
    assert {:error, changeset} =
             SimulationReportCapabilityStatus.validate(%{
               "capability_id" => "capability-1",
               "operational" => true
             })

    assert %{
             required_flow_count: ["can't be blank"],
             missing_flow_count: ["can't be blank"],
             supporting_host_count: ["can't be blank"],
             min_operational_support: ["can't be blank"]
           } = errors_on(changeset)

    assert {:ok, status} =
             SimulationReportCapabilityStatus.validate(%{
               "capability_id" => "capability-1",
               "operational" => true,
               "required_flow_count" => 2,
               "missing_flow_count" => 1,
               "supporting_host_count" => 3,
               "min_operational_support" => 2
             })

    assert %{
             capability_id: "capability-1",
             operational: true,
             required_flow_count: 2,
             missing_flow_count: 1,
             supporting_host_count: 3,
             min_operational_support: 2
           } =
             SimulationReportCapabilityStatus.to_wire(status)
  end

  test "requires the report topology projection and omits the retired operational flow field" do
    refute Map.has_key?(%FetchSimulationReportReply{}, :operational_flows)

    assert {:error, changeset} = FetchSimulationReportReply.validate(%{})
    assert %{topology_projection: ["can't be blank"]} = errors_on(changeset)

    wire = FetchSimulationReportReply.to_wire(%FetchSimulationReportReply{})
    assert Map.has_key?(wire, :topology_projection)
    refute Map.has_key?(wire, :operational_flows)
  end

  defp projection_wire do
    {:ok, wire} =
      @projection_graph_id
      |> projection_graph()
      |> DomainTopologyProjection.project()
      |> TopologyProjection.from_domain()

    wire
  end

  defp projection_graph(graph_id) do
    dmz =
      node(
        @projection_segment_id,
        NetworkSegment,
        %{"name" => "dmz", "cidr" => "10.0.0.0/24"},
        graph_id
      )

    lan =
      node(
        @projection_segment_b_id,
        NetworkSegment,
        %{"name" => "lan", "cidr" => "10.0.1.0/24"},
        graph_id
      )

    host = node(@projection_host_id, Host, %{"name" => "host-a"}, graph_id)
    host_b = node(@projection_host_b_id, Host, %{"name" => "host-b"}, graph_id)

    service =
      node(
        @projection_service_id,
        Service,
        %{"name" => "service", "protocol" => "tcp", "port" => 443},
        graph_id
      )

    service_b =
      node(
        @projection_service_b_id,
        Service,
        %{"name" => "service-b", "protocol" => "tcp", "port" => 5432},
        graph_id
      )

    vulnerability =
      node(
        @projection_vulnerability_id,
        Vulnerability,
        %{"identifier" => "CVE-1", "exploit_probability" => 0.5, "cvss" => cvss()},
        graph_id
      )

    nodes = [dmz, lan, host, host_b, service, service_b, vulnerability]

    edges = [
      edge(@projection_contains_edge_id, dmz, host, Contains),
      edge(@projection_contains_edge_b_id, lan, host_b, Contains),
      edge(@projection_runs_edge_id, host, service, Runs),
      edge(@projection_runs_edge_b_id, host_b, service_b, Runs),
      edge(@projection_reachability_edge_id, dmz, lan, SegmentReachability, %{"protocol" => "tcp"}),
      edge(
        @projection_self_policy_edge_id,
        lan,
        lan,
        SegmentReachability,
        %{"protocol" => "tcp"}
      ),
      edge(
        @projection_vulnerability_edge_id,
        host,
        vulnerability,
        HasVulnerability,
        %{"required_privilege" => "none", "granted_privilege" => "user"}
      )
    ]

    graph(nodes, edges, graph_id)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, &replace_error_option/2)
    end)
  end

  defp replace_error_option({key, value}, message) do
    placeholder = "%{#{key}}"

    if String.contains?(message, placeholder),
      do: String.replace(message, placeholder, to_string(value)),
      else: message
  end

  defp cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "high",
      "integrity_impact" => "none",
      "availability_impact" => "none"
    }
  end
end
