import type { Edge, Node } from "../../contracts.generated/graph";
/** Resolves an unambiguous Host→Service or Service→Vulnerability owner. */
export function resolveOwnership(
  nodes: readonly Node[],
  edges: readonly Edge[],
): Map<string, string> {
  const nodesById = new Map(nodes.map((node) => [node.id, node]));
  const parentIdsByChildId = new Map<string, Set<string>>();

  for (const edge of edges) {
    const parent = nodesById.get(edge.from_id);
    const child = nodesById.get(edge.to_id);
    if (!(
      (edge.type === "Runs" &&
        parent?.type === "Host" &&
        child?.type === "Service") ||
      (edge.type === "HasVulnerability" &&
        parent?.type === "Service" &&
        child?.type === "Vulnerability")
    ))
      continue;

    const parentIds = parentIdsByChildId.get(child.id) ?? new Set<string>();
    parentIds.add(parent.id);
    parentIdsByChildId.set(child.id, parentIds);
  }

  return new Map(
    [...parentIdsByChildId].flatMap(([childId, parentIds]) =>
      parentIds.size === 1 ? [[childId, parentIds.values().next().value!]] : [],
    ),
  );
}
