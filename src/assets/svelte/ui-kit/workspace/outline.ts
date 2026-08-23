export type OutlineDrag<DragData> = { data: DragData };
export type OutlineDrop<DropData> = { data: DropData };

export interface OutlineNode<DragData = unknown> {
  id: string;
  label: string;
  icon: string;
  kind: string;
  groupId: string;
  parentId?: string;
  section?: { key: string; title: string };
  ariaLabel?: string;
  pressed?: boolean;
  drag?: OutlineDrag<DragData>;
}

export interface OutlineGroup<DropData = unknown> {
  id: string;
  label: string;
  icon?: string;
  depth?: number;
  drop?: OutlineDrop<DropData>;
}

export type OutlineGuide = "space" | "line" | "tee" | "elbow";

export type OutlineRow<DragData = unknown, DropData = unknown> =
  | {
      type: "item";
      id: string;
      label: string;
      icon: string;
      kind: string;
      depth: number;
      guides: readonly OutlineGuide[];
      hasChildren: boolean;
      ariaLabel?: string;
      pressed?: boolean;
      drag?: OutlineDrag<DragData>;
    }
  | {
      type: "header";
      id: string;
      label: string;
      icon?: string;
      kind: "folder" | "section" | "group";
      level: number;
      drop?: OutlineDrop<DropData>;
    };

export function buildOutline<DragData = unknown, DropData = unknown>(
  nodes: readonly OutlineNode<DragData>[],
  groups: readonly OutlineGroup<DropData>[],
): OutlineRow<DragData, DropData>[] {
  const groupsById = new Map(groups.map((group) => [group.id, group]));
  const byId = new Map(nodes.map((node) => [node.id, node]));
  const bucketIdOf = (node: OutlineNode<DragData>): string =>
    groupsById.has(node.groupId) ? node.groupId : "root";

  const isRoot = (node: OutlineNode<DragData>): boolean => {
    if (node.parentId === undefined || node.parentId === node.id) return true;
    const parent = byId.get(node.parentId);
    if (!parent || bucketIdOf(parent) !== bucketIdOf(node)) return true;
    const visited = new Set<string>([node.id]);
    let current: OutlineNode<DragData> | undefined = parent;
    while (current) {
      if (visited.has(current.id)) return true;
      visited.add(current.id);
      if (current.parentId === undefined || current.parentId === current.id)
        return false;
      const next = byId.get(current.parentId);
      if (!next || bucketIdOf(next) !== bucketIdOf(current)) return false;
      current = next;
    }
    return false;
  };

  const rootIds = new Set(nodes.filter(isRoot).map((node) => node.id));
  const children = new Map<string, OutlineNode<DragData>[]>();
  for (const node of nodes) {
    if (rootIds.has(node.id)) continue;
    const parent = node.parentId && byId.get(node.parentId);
    if (parent && bucketIdOf(parent) === bucketIdOf(node)) {
      const siblings = children.get(parent.id) ?? [];
      siblings.push(node);
      children.set(parent.id, siblings);
    }
  }

  const rows: OutlineRow<DragData, DropData>[] = [];
  const visit = (
    node: OutlineNode<DragData>,
    depth: number,
    ancestorGuides: OutlineGuide[],
    hasLaterSibling: boolean,
  ): void => {
    rows.push({
      type: "item",
      id: node.id,
      label: node.label,
      icon: node.icon,
      kind: node.kind,
      depth,
      hasChildren: (children.get(node.id)?.length ?? 0) > 0,
      guides:
        depth === 0
          ? []
          : [...ancestorGuides, hasLaterSibling ? "tee" : "elbow"],
      ariaLabel: node.ariaLabel,
      pressed: node.pressed,
      drag: node.drag,
    });
    const childGuides =
      depth === 0
        ? []
        : [
            ...ancestorGuides,
            hasLaterSibling ? ("line" as const) : ("space" as const),
          ];
    const siblings = children.get(node.id) ?? [];
    siblings.forEach((child, index) =>
      visit(child, depth + 1, childGuides, index < siblings.length - 1),
    );
  };

  const visitRoots = (
    roots: readonly OutlineNode<DragData>[],
    depth: number,
  ): void => {
    const ancestorGuides = Array.from(
      { length: Math.max(0, depth - 1) },
      () => "space" as const,
    );
    roots.forEach((node, index) =>
      visit(node, depth, ancestorGuides, index < roots.length - 1),
    );
  };

  const emitBucket = (
    bucketId: string,
    group: OutlineGroup<DropData> | undefined,
    baseDepth: number,
  ): void => {
    const items = nodes.filter((node) => bucketIdOf(node) === bucketId);
    if (items.length === 0 && !group) return;
    if (group) {
      rows.push({
        type: "header",
        id: `group:${group.id}`,
        label: group.label,
        icon: group.icon,
        kind: group.icon ? "folder" : "group",
        level: 2,
        drop: group.drop,
      });
    }

    const roots = items.filter((node) => rootIds.has(node.id));
    const rootItems = roots.filter((node) => !node.section);
    visitRoots(rootItems, baseDepth);

    const sections = new Map<
      string,
      { title: string; nodes: OutlineNode<DragData>[] }
    >();
    for (const node of roots) {
      if (!node.section) continue;
      const group = sections.get(node.section.key) ?? {
        title: node.section.title,
        nodes: [],
      };
      group.nodes.push(node);
      sections.set(node.section.key, group);
    }
    for (const [key, { title, nodes: sectionNodes }] of sections) {
      rows.push({
        type: "header",
        id: `section:${bucketId}:${key}`,
        label: title,
        kind: "section",
        level: group ? 3 : 2,
      });
      visitRoots(sectionNodes, baseDepth + 1);
    }
  };

  for (const group of groups) {
    emitBucket(group.id, group, group.depth ?? 0);
  }
  emitBucket("root", undefined, 0);

  return rows;
}
