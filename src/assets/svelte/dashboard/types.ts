export type ViewMode = "graph" | "list";

export type IconName =
  | "shield" | "search" | "help" | "bell" | "chevron-down" | "cursor" | "link"
  | "server" | "zone" | "copy" | "trash" | "lock" | "align" | "tag" | "play"
  | "graph" | "list" | "fit" | "more" | "chevron-right" | "minus" | "plus";

export interface DashboardDocument {
  id: string;
  title: string;
  kind: "production" | "scenario" | "draft";
  initialSelectionId: string;
}

export interface TopologyNode {
  id: string;
  name: string;
  kind: string;
  address: string;
  zone: string;
  risk: "Critical" | "High" | "Medium" | "Low" | "Untrusted";
  owner: string;
  exposure: string;
  blastRadius: string;
  connections: number;
  x: number;
  y: number;
  status: string;
  critical?: boolean;
}

export interface TopologyEdge {
  id: string;
  sourceId: string;
  targetId: string;
  path: string;
  label: string;
  labelX: number;
  labelY: number;
  warning?: boolean;
}
