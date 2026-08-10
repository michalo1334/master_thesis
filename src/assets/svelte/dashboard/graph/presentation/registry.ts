import type { Component } from "svelte";
import type { Node, Edge } from "../../../contracts.generated";
import type { Selectable } from "../../contract";
import EmptyInspector from "../../inspector/EmptyInspector.svelte";
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
  inspector: Component<any>;
}

export interface EdgePresentation {
  color: string;
  dashArray: string | null;
  inspector: Component<any>;
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

const allInspectors: Record<string, Component<any>> = {};
for (const [key, def] of Object.entries(nodeRegistry)) {
  allInspectors[key] = def.inspector;
}
for (const [key, def] of Object.entries(edgeRegistry)) {
  allInspectors[key] = def.inspector;
}

export function nodePresentation(type: Node["type"]): NodePresentation | null {
  return nodeRegistry[type] ?? null;
}

export function edgePresentation(type: Edge["type"]): EdgePresentation | null {
  return edgeRegistry[type] ?? null;
}

export function inspectorFor(
  selectable: Selectable | undefined,
): Component<any> {
  if (!selectable) return EmptyInspector;
  return allInspectors[selectable.type] ?? EmptyInspector;
}
