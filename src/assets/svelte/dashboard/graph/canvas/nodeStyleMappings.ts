import type { Component } from "svelte";
import type { Node } from "../../contract";
import HostNodeStyle from "../../inspector/hosts/HostNodeStyle.svelte";
import ServiceNodeStyle from "../../inspector/services/ServiceNodeStyle.svelte";
import VulnerabilityNodeStyle from "../../inspector/vulnerabilities/VulnerabilityNodeStyle.svelte";

export interface NodeStyle {
  color: string;
  component: Component;
}

const registry: Record<string, NodeStyle> = {
  Host: { color: "var(--ds-color-node-host)", component: HostNodeStyle },
  Service: {
    color: "var(--ds-color-node-service)",
    component: ServiceNodeStyle,
  },
  Vulnerability: {
    color: "var(--ds-color-node-vulnerability)",
    component: VulnerabilityNodeStyle,
  },
};

export function nodeStyleFor(node: Node): NodeStyle | null {
  return registry[node.type] ?? null;
}
