import type { TopologyGraph } from "./model";

const hostType = "Elixir.NetworkDefense.Nodes.Host";
const serviceType = "Elixir.NetworkDefense.Nodes.Service";
const vulnerabilityType = "Elixir.NetworkDefense.Nodes.Vulnerability";
const reachabilityType =
  "Elixir.NetworkDefense.Relationships.NetworkReachability";
const runsType = "Elixir.NetworkDefense.Relationships.Runs";
const vulnerabilityRelationshipType =
  "Elixir.NetworkDefense.Relationships.HasVulnerability";

export function createDemoTopologyGraph(id: string): TopologyGraph {
  return {
    id,
    title: "Demo topology",
    lockVersion: 1,
    nodes: [
      {
        id: `${id}-host-gateway`,
        graphId: id,
        type: hostType,
        data: { name: "Gateway host" },
        viewData: { x_pos: 100, y_pos: 180 },
      },
      {
        id: `${id}-host-application`,
        graphId: id,
        type: hostType,
        data: { name: "Application host" },
        viewData: { x_pos: 360, y_pos: 330 },
      },
      {
        id: `${id}-service-api`,
        graphId: id,
        type: serviceType,
        data: { name: "API", protocol: "tcp", port: 8443 },
        viewData: { x_pos: 620, y_pos: 220 },
      },
      {
        id: `${id}-vulnerability-api`,
        graphId: id,
        type: vulnerabilityType,
        data: {
          identifier: "CVE-2024-0001",
          cvss_score: 8.1,
          exploit_probability: 0.42,
        },
        viewData: { x_pos: 880, y_pos: 220 },
      },
    ],
    edges: [
      {
        id: `${id}-edge-reachability`,
        graphId: id,
        fromId: `${id}-host-gateway`,
        toId: `${id}-service-api`,
        type: reachabilityType,
        data: {},
      },
      {
        id: `${id}-edge-runs`,
        graphId: id,
        fromId: `${id}-host-application`,
        toId: `${id}-service-api`,
        type: runsType,
        data: {},
      },
      {
        id: `${id}-edge-vulnerability`,
        graphId: id,
        fromId: `${id}-service-api`,
        toId: `${id}-vulnerability-api`,
        type: vulnerabilityRelationshipType,
        data: {},
      },
    ],
  };
}
