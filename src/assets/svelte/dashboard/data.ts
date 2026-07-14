import type { DashboardDocument, TopologyEdge, TopologyNode } from "./types";

export const dashboardDocuments: DashboardDocument[] = [
  { id: "production", title: "Production topology", kind: "production", initialSelectionId: "api" },
  { id: "scenario-b", title: "Segmentation scenario B", kind: "scenario", initialSelectionId: "database" },
  { id: "draft", title: "Research topology", kind: "draft", initialSelectionId: "edge-fw" }
];

export const topologyNodes: TopologyNode[] = [
  { id: "internet", name: "Internet", kind: "External boundary", address: "Any", zone: "External", risk: "Untrusted", owner: "Unmanaged", exposure: "Public", blastRadius: "—", connections: 1, x: 70, y: 170, status: "Exposed" },
  { id: "edge-fw", name: "Edge FW", kind: "Security appliance", address: "10.0.10.1", zone: "DMZ / VLAN 10", risk: "High", owner: "Network team", exposure: "Public", blastRadius: "42%", connections: 2, x: 300, y: 138, status: "2 findings", critical: true },
  { id: "vpn", name: "VPN", kind: "Security appliance", address: "10.0.10.8", zone: "DMZ / VLAN 10", risk: "Low", owner: "Network team", exposure: "Public", blastRadius: "26%", connections: 1, x: 300, y: 376, status: "Hardened" },
  { id: "web", name: "Web gateway", kind: "Compute asset", address: "10.0.20.14", zone: "Application / VLAN 20", risk: "Medium", owner: "Platform team", exposure: "DMZ ingress", blastRadius: "51%", connections: 2, x: 582, y: 132, status: "1 finding" },
  { id: "api", name: "App API", kind: "Compute asset", address: "10.0.20.21", zone: "Application / VLAN 20", risk: "Critical", owner: "Platform team", exposure: "Internal", blastRadius: "68%", connections: 4, x: 760, y: 280, status: "Critical asset", critical: true },
  { id: "worker", name: "Worker pool", kind: "Compute group", address: "Dynamic", zone: "Application / VLAN 20", risk: "Low", owner: "Platform team", exposure: "Internal", blastRadius: "34%", connections: 2, x: 558, y: 453, status: "Healthy" },
  { id: "database", name: "Primary DB", kind: "Database asset", address: "10.0.30.10", zone: "Data / VLAN 30", risk: "Critical", owner: "Data services", exposure: "Restricted", blastRadius: "84%", connections: 1, x: 904, y: 219, status: "Crown jewel", critical: true },
  { id: "cache", name: "Redis cache", kind: "Data service", address: "10.0.30.18", zone: "Data / VLAN 30", risk: "Medium", owner: "Data services", exposure: "Restricted", blastRadius: "47%", connections: 1, x: 904, y: 402, status: "Review ACL" }
];

export const topologyEdges: TopologyEdge[] = [
  { id: "internet-fw", sourceId: "internet", targetId: "edge-fw", path: "M190 206 C245 206 243 174 300 174", label: "HTTPS · 443", labelX: 235, labelY: 181 },
  { id: "fw-web", sourceId: "edge-fw", targetId: "web", path: "M420 174 C470 174 530 168 582 168", label: "ALLOW", labelX: 481, labelY: 159 },
  { id: "web-api", sourceId: "web", targetId: "api", path: "M702 168 C742 168 727 316 760 316", label: "API · 8443", labelX: 720, labelY: 244 },
  { id: "api-db", sourceId: "api", targetId: "database", path: "M880 316 C900 316 883 255 904 255", label: "TCP · 5432", labelX: 870, labelY: 281, warning: true },
  { id: "api-worker", sourceId: "api", targetId: "worker", path: "M760 340 C720 366 710 463 678 477", label: "AMQP", labelX: 698, labelY: 411 },
  { id: "worker-cache", sourceId: "worker", targetId: "cache", path: "M678 489 C795 489 800 438 904 438", label: "TCP · 6379", labelX: 786, labelY: 465 },
  { id: "vpn-api", sourceId: "vpn", targetId: "api", path: "M420 412 C560 412 628 332 760 328", label: "ADMIN · 22", labelX: 560, labelY: 377, warning: true }
];
