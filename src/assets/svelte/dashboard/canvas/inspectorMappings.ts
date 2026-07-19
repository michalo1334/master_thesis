import type { Component } from "svelte";
import type { Selectable } from "../contract";
import HostInspector from "../hosts/HostInspector.svelte";
import ServiceInspector from "../services/ServiceInspector.svelte";
import VulnerabilityInspector from "../vulnerabilities/VulnerabilityInspector.svelte";
import CanvasEdgeInspector from "./inspectors/CanvasEdgeInspector.svelte";
import EmptyInspector from "../EmptyInspector.svelte";

const registry: Record<string, Component<any>> = {
  Host: HostInspector,
  Service: ServiceInspector,
  Vulnerability: VulnerabilityInspector,
  Runs: CanvasEdgeInspector,
  NetworkReachability: CanvasEdgeInspector,
  HasVulnerability: CanvasEdgeInspector,
};

export function inspectorFor(
  selectable: Selectable | undefined,
): Component<any> {
  return selectable === undefined
    ? EmptyInspector
    : (registry[selectable.type] ?? EmptyInspector);
}
