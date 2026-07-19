import type { Component } from "svelte";
import type { Node } from "../contract";
import HostNodeInfo from "./HostNodeInfo.svelte";
import ServiceNodeInfo from "./ServiceNodeInfo.svelte";
import VulnerabilityNodeInfo from "./VulnerabilityNodeInfo.svelte";

const registry: Record<string, Component<any>> = {
  Host: HostNodeInfo,
  Service: ServiceNodeInfo,
  Vulnerability: VulnerabilityNodeInfo,
};

export function nodeInfoFor(node: Node): Component<any> | null {
  return registry[node.type] ?? null;
}
