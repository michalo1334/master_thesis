defmodule NetworkDefense.Graph.TopologyProjectionTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.{Graph, TopologyProjection}

  alias NetworkDefense.Nodes.{
    Credential,
    Host,
    MissionCapability,
    NetworkSegment,
    Service,
    Vulnerability
  }

  alias NetworkDefense.Relationships.{
    AuthenticatesTo,
    Contains,
    HasVulnerability,
    NetworkReachability,
    Runs,
    SegmentReachability,
    StoresCredential,
    Supports
  }

  import NetworkDefense.GraphFixtures, only: [edge: 4, edge: 5, graph: 2, node: 3]

  describe "topology elements" do
    test "projects membership, ownership, counts, and order" do
      {nodes, edges} = network_parts()
      graph = graph(nodes, edges)
      projection = TopologyProjection.project(graph)

      assert projection.segments == [
               %{
                 id: "segment",
                 host_ids: ["host-a"],
                 host_count: 1,
                 service_count: 1,
                 context_count: 1
               },
               %{
                 id: "segment-b",
                 host_ids: ["host-b"],
                 host_count: 1,
                 service_count: 0,
                 context_count: 0
               }
             ]

      assert projection.hosts == [
               %{
                 id: "host-a",
                 segment_id: "segment",
                 service_ids: ["service"],
                 service_count: 1,
                 context_count: 1
               },
               %{
                 id: "host-b",
                 segment_id: "segment-b",
                 service_ids: [],
                 service_count: 0,
                 context_count: 0
               }
             ]

      assert projection.services == [%{id: "service", host_id: "host-a"}]

      assert projection.attachments == [
               %{
                 id: "vulnerability",
                 kind: :vulnerability,
                 anchors: [
                   %{
                     node_id: "service",
                     edge_id: "has-vulnerability",
                     relationship_type: :has_vulnerability
                   }
                 ]
               }
             ]

      assert projection.policy_groups == [
               %{
                 from_segment_id: "segment",
                 to_segment_id: "segment-b",
                 edge_ids: ["reachability"]
               }
             ]

      assert projection.flow_groups == []
      assert projection.issues == []
    end

    test "groups segment policies by segment pair and keeps self policies" do
      {nodes, edges} = network_parts()
      [dmz, lan, _host_a, _host_b, _service, _vulnerability] = nodes

      edges =
        edges ++
          [
            edge("policy-b", dmz, lan, SegmentReachability, %{"protocol" => "any"}),
            edge("self-policy", lan, lan, SegmentReachability, %{"protocol" => "tcp"})
          ]

      projection = TopologyProjection.project(graph(nodes, edges))

      assert projection.policy_groups == [
               %{
                 from_segment_id: "segment",
                 to_segment_id: "segment-b",
                 edge_ids: ["policy-b", "reachability"]
               },
               %{
                 from_segment_id: "segment-b",
                 to_segment_id: "segment-b",
                 edge_ids: ["self-policy"]
               }
             ]

      assert projection.flow_groups == []
      assert projection.issues == []
    end

    test "anchors a credential to its storage host and its service" do
      dmz = segment("segment")
      host_a = host("host-a")
      service = service("service")
      credential = credential("credential")

      edges = [
        edge("contains", dmz, host_a, Contains),
        edge("runs", host_a, service, Runs),
        edge("stores", host_a, credential, StoresCredential, %{"required_privilege" => "user"}),
        edge("auth", credential, service, AuthenticatesTo, %{"granted_privilege" => "user"})
      ]

      projection = TopologyProjection.project(graph([dmz, host_a, service, credential], edges))

      assert projection.attachments == [
               %{
                 id: "credential",
                 kind: :credential,
                 anchors: [
                   %{node_id: "host-a", edge_id: "stores", relationship_type: :stores_credential},
                   %{node_id: "service", edge_id: "auth", relationship_type: :authenticates_to}
                 ]
               }
             ]

      assert [%{id: "host-a", context_count: 1}] = projection.hosts
      assert [%{id: "segment", context_count: 1}] = projection.segments
      assert projection.issues == []
    end

    test "anchors a mission capability to every supporting host" do
      dmz = segment("segment")
      host_a = host("host-a")
      host_b = host("host-b")
      capability = capability("capability")

      edges = [
        edge("contains", dmz, host_a, Contains),
        edge("contains-b", dmz, host_b, Contains),
        edge("supports-a", host_a, capability, Supports),
        edge("supports-b", host_b, capability, Supports)
      ]

      projection = TopologyProjection.project(graph([dmz, host_a, host_b, capability], edges))

      assert projection.attachments == [
               %{
                 id: "capability",
                 kind: :mission_capability,
                 anchors: [
                   %{node_id: "host-a", edge_id: "supports-a", relationship_type: :supports},
                   %{node_id: "host-b", edge_id: "supports-b", relationship_type: :supports}
                 ]
               }
             ]

      assert Enum.sort_by(projection.hosts, & &1.id) == [
               %{
                 id: "host-a",
                 segment_id: "segment",
                 service_ids: [],
                 service_count: 0,
                 context_count: 1
               },
               %{
                 id: "host-b",
                 segment_id: "segment",
                 service_ids: [],
                 service_count: 0,
                 context_count: 1
               }
             ]

      # Both anchors resolve to the same segment, but the attachment counts once.
      assert [%{id: "segment", context_count: 1}] = projection.segments
      assert projection.issues == []
    end
  end

  describe "operational flows" do
    test "groups materialized flows by source and target host" do
      graph = flow_network()
      projection = TopologyProjection.project(graph)

      assert [
               %{
                 source_host_id: "host-a",
                 target_host_id: "host-b",
                 service_ids: ["service-b"],
                 flow_ids: [_flow_id]
               }
             ] = projection.flow_groups

      # The unhosted service never becomes a flow endpoint.
      assert [%{id: "orphan-service", host_id: nil}] =
               projection.services
               |> Enum.filter(&(&1.id == "orphan-service"))
    end

    test "ignores flows to services without a unique host" do
      dmz = segment("segment")
      lan = segment("segment-b")
      host_a = host("host-a")
      host_b = host("host-b")
      service_b = service("service-b", "tcp", 5432)
      shared = service("service-x", "tcp", 9000)

      nodes = [dmz, lan, host_a, host_b, service_b, shared]

      edges = [
        edge("contains", dmz, host_a, Contains),
        edge("contains-b", lan, host_b, Contains),
        edge("runs-b", host_b, service_b, Runs),
        edge("runs-x-a", host_a, shared, Runs),
        edge("runs-x-b", host_b, shared, Runs),
        edge("reachability", dmz, lan, SegmentReachability, %{"protocol" => "tcp"})
      ]

      projection = TopologyProjection.project(draft(nodes, edges))

      assert [
               %{
                 source_host_id: "host-a",
                 target_host_id: "host-b",
                 service_ids: ["service-b"],
                 flow_ids: [_flow_id]
               }
             ] = projection.flow_groups

      assert projection.issues == [
               %{
                 code: :service_multiple_hosts,
                 severity: :warning,
                 entity_id: "service-x",
                 related_ids: ["host-a", "host-b"]
               }
             ]

      assert [%{id: "service-x", host_id: nil}] =
               projection.services |> Enum.filter(&(&1.id == "service-x"))
    end

    test "does not mutate the canonical graph" do
      graph = flow_network()
      _ = TopologyProjection.project(graph)

      refute Enum.any?(graph |> Graph.edges(), &(&1.type == NetworkReachability))
    end
  end

  describe "placement issues" do
    test "flags a host without a segment" do
      dmz = segment("segment")
      host_a = host("host-a")
      host_c = host("host-c")

      projection =
        TopologyProjection.project(
          draft([dmz, host_a, host_c], [edge("contains", dmz, host_a, Contains)])
        )

      assert projection.issues == [
               %{
                 code: :host_without_segment,
                 severity: :warning,
                 entity_id: "host-c",
                 related_ids: []
               }
             ]

      assert [%{id: "host-c", segment_id: nil}] =
               projection.hosts |> Enum.filter(&(&1.id == "host-c"))

      refute Enum.any?(projection.segments, &(&1.host_ids |> Enum.member?("host-c")))
    end

    test "flags a host in multiple segments" do
      dmz = segment("segment")
      lan = segment("segment-b")
      host_d = host("host-d")

      projection =
        TopologyProjection.project(
          draft([dmz, lan, host_d], [
            edge("contains-a", dmz, host_d, Contains),
            edge("contains-b", lan, host_d, Contains)
          ])
        )

      assert projection.issues == [
               %{
                 code: :host_multiple_segments,
                 severity: :warning,
                 entity_id: "host-d",
                 related_ids: ["segment", "segment-b"]
               }
             ]

      assert [%{id: "host-d", segment_id: nil}] =
               projection.hosts |> Enum.filter(&(&1.id == "host-d"))

      # Unplaced hosts are excluded from every segment.
      assert all_segments_without(projection.segments, "host-d")
    end

    test "flags a service without a host" do
      projection = TopologyProjection.project(draft([service("service-y")], []))

      assert projection.issues == [
               %{
                 code: :service_without_host,
                 severity: :warning,
                 entity_id: "service-y",
                 related_ids: []
               }
             ]

      assert [%{id: "service-y", host_id: nil}] = projection.services
    end

    test "flags a service run by multiple hosts" do
      dmz = segment("segment")
      lan = segment("segment-b")
      host_a = host("host-a")
      host_b = host("host-b")
      shared = service("service-x", "tcp", 9000)

      projection =
        TopologyProjection.project(
          draft([dmz, lan, host_a, host_b, shared], [
            edge("contains", dmz, host_a, Contains),
            edge("contains-b", lan, host_b, Contains),
            edge("runs-a", host_a, shared, Runs),
            edge("runs-b", host_b, shared, Runs)
          ])
        )

      assert projection.issues == [
               %{
                 code: :service_multiple_hosts,
                 severity: :warning,
                 entity_id: "service-x",
                 related_ids: ["host-a", "host-b"]
               }
             ]

      assert [%{id: "service-x", host_id: nil}] = projection.services
      refute Enum.any?(projection.hosts, &(&1.service_ids |> Enum.member?("service-x")))
    end

    test "flags context nodes without anchors" do
      projection =
        TopologyProjection.project(
          draft(
            [capability("capability"), credential("credential"), vulnerability("vulnerability")],
            []
          )
        )

      assert projection.issues == [
               %{
                 code: :context_without_anchor,
                 severity: :warning,
                 entity_id: "capability",
                 related_ids: []
               },
               %{
                 code: :context_without_anchor,
                 severity: :warning,
                 entity_id: "credential",
                 related_ids: []
               },
               %{
                 code: :context_without_anchor,
                 severity: :warning,
                 entity_id: "vulnerability",
                 related_ids: []
               }
             ]
    end

    test "flags context anchored only to unplaceable services" do
      unhosted = service("service-z")
      vulnerability = vulnerability("vulnerability-z")

      projection =
        TopologyProjection.project(
          draft([unhosted, vulnerability], [
            edge("has-vulnerability", unhosted, vulnerability, HasVulnerability, %{
              "required_privilege" => "none",
              "granted_privilege" => "user"
            })
          ])
        )

      # The unhosted service is reported as well; issues are sorted by code.
      assert projection.issues == [
               %{
                 code: :context_without_anchor,
                 severity: :warning,
                 entity_id: "vulnerability-z",
                 related_ids: ["service-z"]
               },
               %{
                 code: :service_without_host,
                 severity: :warning,
                 entity_id: "service-z",
                 related_ids: []
               }
             ]

      # The anchor still exists, it just resolves to no host.
      assert [%{id: "vulnerability-z", anchors: [_anchor]}] = projection.attachments
    end
  end

  describe "determinism" do
    test "identical graphs produce identical projections regardless of input order" do
      {nodes, edges} = network_parts()

      first = TopologyProjection.project(graph(nodes, edges))
      second = TopologyProjection.project(graph(Enum.reverse(nodes), Enum.reverse(edges)))

      assert first == second
    end

    test "projects an empty graph to empty arrays" do
      projection = TopologyProjection.project(graph([], []))

      assert projection == %TopologyProjection{
               segments: [],
               hosts: [],
               services: [],
               attachments: [],
               policy_groups: [],
               flow_groups: [],
               issues: []
             }
    end
  end

  defp all_segments_without(projection_segments, host_id) do
    Enum.all?(projection_segments, &(not Enum.member?(&1.host_ids, host_id)))
  end

  defp segment(id) do
    node(id, NetworkSegment, %{"name" => id, "cidr" => "10.0.0.0/24"})
  end

  defp segment(id, cidr) do
    node(id, NetworkSegment, %{"name" => id, "cidr" => cidr})
  end

  defp host(id) do
    node(id, Host, %{"name" => id})
  end

  defp service(id, protocol \\ "tcp", port \\ 443) do
    node(id, Service, %{"name" => id, "protocol" => protocol, "port" => port})
  end

  defp vulnerability(id) do
    node(id, Vulnerability, %{
      "identifier" => id,
      "exploit_probability" => 0.5,
      "cvss" => cvss_data()
    })
  end

  defp credential(id) do
    node(id, Credential, %{"identifier" => id, "credential_type" => "password"})
  end

  defp capability(id) do
    node(id, MissionCapability, %{
      "name" => id,
      "impact_weight" => 2.0,
      "min_operational_support" => 1,
      "required_flows" => []
    })
  end

  defp cvss_data do
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

  defp network_parts do
    dmz = segment("segment", "10.0.0.0/24")
    lan = segment("segment-b", "10.0.1.0/24")
    host_a = host("host-a")
    host_b = host("host-b")
    service = service("service")
    vulnerability = vulnerability("vulnerability")

    nodes = [dmz, lan, host_a, host_b, service, vulnerability]

    edges = [
      edge("runs", host_a, service, Runs),
      edge(
        "has-vulnerability",
        service,
        vulnerability,
        HasVulnerability,
        %{"required_privilege" => "none", "granted_privilege" => "user"}
      ),
      edge("reachability", dmz, lan, SegmentReachability, %{"protocol" => "tcp"}),
      edge("contains", dmz, host_a, Contains),
      edge("contains-b", lan, host_b, Contains)
    ]

    {nodes, edges}
  end

  defp flow_network do
    dmz = segment("segment", "10.0.0.0/24")
    lan = segment("segment-b", "10.0.1.0/24")
    host_a = host("host-a")
    host_b = host("host-b")
    service = service("service", "tcp", 443)
    service_b = service("service-b", "tcp", 5432)
    orphan = service("orphan-service", "tcp", 8080)

    nodes = [dmz, lan, host_a, host_b, service, service_b, orphan]

    edges = [
      edge("runs", host_a, service, Runs),
      edge("runs-b", host_b, service_b, Runs),
      edge("reachability", dmz, lan, SegmentReachability, %{"protocol" => "tcp"}),
      edge("contains", dmz, host_a, Contains),
      edge("contains-b", lan, host_b, Contains)
    ]

    graph(nodes, edges)
  end

  defp draft(nodes, edges) do
    {:ok, graph} = Graph.hydrate(%Graph{id: "graph"}, nodes, edges, false)
    graph
  end
end
