defmodule NetworkDefenseWeb.DashboardContractsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gen.Contracts.Registry
  alias NetworkDefense.Contracts
  alias NetworkDefense.Graph.Edge
  alias NetworkDefense.Graph.Contracts.GraphContract
  alias NetworkDefense.Graph.Contracts.SaveGraphContract
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Graph.Node
  alias NetworkDefense.Nodes.Credential
  alias NetworkDefense.Nodes.Host
  alias NetworkDefense.Nodes.NetworkSegment
  alias NetworkDefense.Nodes.Service
  alias NetworkDefense.Nodes.Vulnerability
  alias NetworkDefense.Optimization.OptimizationRun

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    Contains,
    HasVulnerability,
    Runs,
    SegmentReachability,
    StoresCredential
  }

  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest

  alias NetworkDefenseWeb.Web.Contracts.{
    FetchGraphProjectionPayload,
    FetchGraphProjectionReply,
    FetchOptimizationReportPayload,
    FetchOptimizationReportReply,
    FetchOptimizationRunsPayload,
    OpenGraphReply,
    OptimizationCompletedEvent,
    RunWorkflowRequest,
    SaveGraphPayload
  }

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

  test "accepts only the combined analysis workflow template" do
    attrs = %{
      "template" => "combined_analysis",
      "graph_revision_id" => @graph_id,
      "correlation_id" => "workflow-1",
      "simulation_params" => %{
        "monte_carlo_trials" => 1,
        "iterations_per_run" => 1,
        "initial_foothold_node_id" => @host_id,
        "seed" => 1,
        "generate_seed" => false,
        "max_attempts" => 1
      },
      "optimization_params" => %{
        "strategy" => "cvss",
        "budget" => 1
      }
    }

    assert {:ok, %RunWorkflowRequest{template: "combined_analysis"}} =
             RunWorkflowRequest.validate(attrs)

    assert {:error, changeset} =
             RunWorkflowRequest.validate(Map.put(attrs, "template", "two_step"))

    assert %{template: ["is invalid"]} = errors_on(changeset)
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

  test "requires optimization report fetch identifiers to be UUIDs" do
    assert {:error, changeset} =
             FetchOptimizationReportPayload.validate(%{
               "document_id" => @graph_id,
               "optimization_id" => "not-a-uuid",
               "graph_revision_id" => "graph-1"
             })

    assert %{optimization_id: ["is invalid"], graph_revision_id: ["is invalid"]} =
             errors_on(changeset)
  end

  test "rejects non-UUID graph revision ids in optimization run fetch" do
    assert {:error, changeset} =
             FetchOptimizationRunsPayload.validate(%{"graph_revision_ids" => ["not-a-uuid"]})

    assert %{graph_revision_ids: ["contains an invalid UUID"]} = errors_on(changeset)
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

  test "accepts a graph projection fetch payload with a UUID revision id" do
    assert {:ok, %FetchGraphProjectionPayload{graph_revision_id: @graph_id}} =
             FetchGraphProjectionPayload.validate(%{"graph_revision_id" => @graph_id})
  end

  test "rejects a graph projection fetch payload without a UUID revision id" do
    assert {:error, changeset} = FetchGraphProjectionPayload.validate(%{})
    assert %{graph_revision_id: ["can't be blank"]} = errors_on(changeset)

    assert {:error, changeset} =
             FetchGraphProjectionPayload.validate(%{"graph_revision_id" => "not-a-uuid"})

    assert %{graph_revision_id: ["is invalid"]} = errors_on(changeset)
  end

  test "round trips an ok graph projection reply with endpoint records" do
    attrs = %{
      "status" => "ok",
      "segments" => [%{"id" => @segment_id}, %{"id" => @segment_b_id}],
      "hosts" => [%{"id" => @host_id}],
      "policy_links" => [
        %{"id" => @reachability_edge_id, "from_id" => @segment_b_id, "to_id" => @segment_id}
      ],
      "operational_flows" => [
        %{"id" => @runs_edge_id, "from_id" => @host_id, "to_id" => @service_id}
      ]
    }

    assert {:ok, reply} = FetchGraphProjectionReply.validate(attrs)

    assert %{
             status: "ok",
             segments: [%{id: @segment_id}, %{id: @segment_b_id}],
             hosts: [%{id: @host_id}],
             policy_links: [
               %{id: @reachability_edge_id, from_id: @segment_b_id, to_id: @segment_id}
             ],
             operational_flows: [%{id: @runs_edge_id, from_id: @host_id, to_id: @service_id}]
           } = FetchGraphProjectionReply.to_wire(reply)
  end

  test "accepts an error status projection reply with empty collections" do
    assert {:ok, reply} = FetchGraphProjectionReply.validate(%{"status" => "not_found"})

    assert %{
             status: "not_found",
             segments: [],
             hosts: [],
             policy_links: [],
             operational_flows: []
           } =
             FetchGraphProjectionReply.to_wire(reply)
  end

  test "rejects a graph projection reply with an unknown status" do
    assert {:error, changeset} = FetchGraphProjectionReply.validate(%{"status" => "stale"})
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end

  test "requires capability status counts and minimum support" do
    assert {:error, changeset} =
             NetworkDefenseWeb.Web.Contracts.SimulationReportCapabilityStatus.validate(%{
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
             NetworkDefenseWeb.Web.Contracts.SimulationReportCapabilityStatus.validate(%{
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
           } = NetworkDefenseWeb.Web.Contracts.SimulationReportCapabilityStatus.to_wire(status)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
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
