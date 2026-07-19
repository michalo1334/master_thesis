import type { Component } from "svelte";
import type { Selectable } from "../../contract";
import HostInspector from "./HostInspector.svelte";
import ServiceInspector from "./ServiceInspector.svelte";
import VulnerabilityInspector from "./VulnerabilityInspector.svelte";
import CanvasEdgeInspector from "./CanvasEdgeInspector.svelte";

const registry: Record<string, Component<any>> = {
  Host: HostInspector,
  Service: ServiceInspector,
  Vulnerability: VulnerabilityInspector,
  Runs: CanvasEdgeInspector,
  "Network Reachability": CanvasEdgeInspector,
  "Has Vulnerability": CanvasEdgeInspector,
};

export function inspectorFor(selectable: Selectable): Component<any> | null {
  return registry[selectable.type] ?? null;
}
