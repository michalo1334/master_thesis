import type { Live } from "live_svelte";
import type { IconName } from "../types";

export type CommandSource = "ribbon" | "context-menu" | "shortcut" | "palette";
export type TopologyLayout = "layered" | "force-directed" | "radial";
export type TopologyTool = "select" | "connect";

export interface ActiveDocument {
  id: string;
  title: string;
  type: "topology" | "simulation";
}

export interface SelectedTopologyObject {
  id: string;
  name: string;
}

export interface DashboardUiState {
  currentTool: TopologyTool;
  topologyLayout: TopologyLayout;
  showZoneBoundaries: boolean;
  inspectorVisible: boolean;
  presentation: "graph" | "list";
  lastSelectionAction?: "duplicate" | "remove" | "lock" | "align";
}

export interface CommandContext {
  activeDocument?: ActiveDocument;
  selectedObject?: SelectedTopologyObject;
  ui: DashboardUiState;
  source: CommandSource;
  live?: Live;
  setUi: (update: Partial<DashboardUiState>) => void;
  setSelectedObject: (object?: SelectedTopologyObject) => void;
}

export type CommandId =
  | "select-tool"
  | "connect-tool"
  | "set-topology-layout"
  | "toggle-zone-boundaries"
  | "toggle-inspector"
  | "show-graph"
  | "show-list"
  | "select-topology-object"
  | "clear-selection"
  | "duplicate-selection"
  | "remove-selection"
  | "lock-selection"
  | "align-selection"
  | "run-simulation"
  | "optimize-defense";

export interface CommandArguments {
  "select-tool": undefined;
  "connect-tool": undefined;
  "set-topology-layout": { layout: TopologyLayout };
  "toggle-zone-boundaries": undefined;
  "toggle-inspector": undefined;
  "show-graph": undefined;
  "show-list": undefined;
  "select-topology-object": { object: SelectedTopologyObject };
  "clear-selection": undefined;
  "duplicate-selection": undefined;
  "remove-selection": undefined;
  "lock-selection": undefined;
  "align-selection": undefined;
  "run-simulation": undefined;
  "optimize-defense": undefined;
}

export interface CommandDefinition<Id extends CommandId = CommandId> {
  id: Id;
  label: string;
  icon?: IconName;
  undo?: { label: string };
  isAvailable: (context: CommandContext) => boolean;
  execute: (context: CommandContext, args: CommandArguments[Id]) => void;
}
