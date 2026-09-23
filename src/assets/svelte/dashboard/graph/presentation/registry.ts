import type { Edge, Node } from "../../../contracts.generated/graph";
import type { Component } from "svelte";
import { hostNode } from "./nodes/HostNode";
import { serviceNode } from "./nodes/ServiceNode";
import { vulnerabilityNode } from "./nodes/VulnerabilityNode";
import { credentialNode } from "./nodes/CredentialNode";
import { networkSegmentNode } from "./nodes/NetworkSegmentNode";
import { missionCapabilityNode } from "./nodes/MissionCapabilityNode";
import { runsEdge } from "./edges/RunsEdge";
import { segmentReachabilityEdge } from "./edges/SegmentReachabilityEdge";
import { hasVulnerabilityEdge } from "./edges/HasVulnerabilityEdge";
import { storesCredentialEdge } from "./edges/StoresCredentialEdge";
import { authenticatesToEdge } from "./edges/AuthenticatesToEdge";
import { containsEdge } from "./edges/ContainsEdge";
import { supportsEdge } from "./edges/SupportsEdge";

export interface NodePresentation {
  color: string;
  glyph: Component;
  info: Component<any>;
}

export interface EdgePresentation {
  color: string;
  dashArray: string | null;
  label?: (edge: Edge) => string;
}

const nodeRegistry = {
  Host: hostNode,
  Service: serviceNode,
  Vulnerability: vulnerabilityNode,
  Credential: credentialNode,
  NetworkSegment: networkSegmentNode,
  MissionCapability: missionCapabilityNode,
} satisfies Record<Node["type"], NodePresentation>;

const edgeRegistry = {
  Runs: runsEdge,
  SegmentReachability: segmentReachabilityEdge,
  HasVulnerability: hasVulnerabilityEdge,
  StoresCredential: storesCredentialEdge,
  AuthenticatesTo: authenticatesToEdge,
  Contains: containsEdge,
  Supports: supportsEdge,
} satisfies Record<Edge["type"], EdgePresentation>;

export function nodePresentation(type: Node["type"]): NodePresentation | null {
  return nodeRegistry[type] ?? null;
}

export function edgePresentation(type: Edge["type"]): EdgePresentation | null {
  return edgeRegistry[type] ?? null;
}
