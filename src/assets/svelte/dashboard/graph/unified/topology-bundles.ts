import type { TopologyScene } from "../topology-scene";

/**
 * One directed connection summary between two ordered segments.
 *
 * The canvas draws a far-zoom bundle instead of the detailed policy and
 * operational-flow lines. Every member comes from an accepted projection group,
 * so a bundle never adds graph meaning.
 */
export interface TopologyConnectionDetailRow {
  serviceId: string;
  serviceLabel: string;
  sourceHostId: string;
  sourceHostLabel: string;
  targetHostId: string;
  targetHostLabel: string;
}

/** Visible label for an accepted projected connection. */
export function connectionDetailLabel(
  row: TopologyConnectionDetailRow,
): string {
  return `${row.serviceLabel} · ${row.sourceHostLabel} → ${row.targetHostLabel}`;
}

export interface TopologyConnectionBundle {
  /** Stable key: `<from segment id>:<to segment id>`. */
  key: string;
  fromSegmentId: string;
  toSegmentId: string;
  /** True when source and target are the same segment. No loop line is drawn. */
  isSelf: boolean;
  /** Unique policy edge ids that join the pair, sorted. */
  policyEdgeIds: string[];
  /** Unique operational flow ids that join the pair, sorted. */
  flowIds: string[];
  /** Unique service ids the flows on the pair carry, sorted. */
  serviceIds: string[];
  /** Service labels in `serviceIds` order. */
  serviceLabels: string[];
  /** Accepted flow details for the pair, sorted and deduplicated. */
  detailRows: TopologyConnectionDetailRow[];
  /** Unique policy edges plus unique flows. */
  connectionCount: number;
}

interface BundleAccumulator {
  fromSegmentId: string;
  toSegmentId: string;
  policyEdgeIds: Set<string>;
  flowIds: Set<string>;
  /** Service labels by service id, so one service counts once. */
  serviceLabels: Map<string, string>;
  /** One detail per displayed service-source-target label combination. */
  detailRows: Map<string, TopologyConnectionDetailRow>;
}

/**
 * Groups accepted projection groups into directed segment-pair bundles.
 *
 * Policy groups supply policy edge ids. Flow groups supply flow ids and the
 * labels of the services those flows reach. A flow group whose host has no
 * projected segment contributes to no bundle, because the bundle pair comes
 * only from projected host membership. Every array is sorted and the result is
 * ordered by key, so the same scene always produces the same bundles.
 */
export function buildConnectionBundles(
  scene: TopologyScene,
): TopologyConnectionBundle[] {
  const segmentByHost = new Map<string, string>();
  for (const segment of scene.segments) {
    for (const host of segment.hosts) segmentByHost.set(host.id, segment.id);
  }

  const bundles = new Map<string, BundleAccumulator>();
  const bundleFor = (
    fromSegmentId: string,
    toSegmentId: string,
  ): BundleAccumulator => {
    const key = `${fromSegmentId}:${toSegmentId}`;
    let bundle = bundles.get(key);
    if (!bundle) {
      bundle = {
        fromSegmentId,
        toSegmentId,
        policyEdgeIds: new Set(),
        flowIds: new Set(),
        serviceLabels: new Map(),
        detailRows: new Map(),
      };
      bundles.set(key, bundle);
    }
    return bundle;
  };

  for (const group of scene.policyGroups) {
    const bundle = bundleFor(
      group.group.from_segment_id,
      group.group.to_segment_id,
    );
    for (const edge of group.edges) bundle.policyEdgeIds.add(edge.id);
  }

  for (const group of scene.flowGroups) {
    const from = segmentByHost.get(group.group.source_host_id);
    const to = segmentByHost.get(group.group.target_host_id);
    if (!from || !to) continue;
    const bundle = bundleFor(from, to);
    for (const flowId of group.flowIds) bundle.flowIds.add(flowId);
    for (const service of group.services) {
      bundle.serviceLabels.set(service.id, service.node.data.name);
    }
    for (const row of connectionDetailsForGroups([group])) {
      addConnectionDetail(bundle.detailRows, row);
    }
  }

  return [...bundles.entries()]
    .map(([key, bundle]) => {
      const policyEdgeIds = [...bundle.policyEdgeIds].sort(compareStrings);
      const flowIds = [...bundle.flowIds].sort(compareStrings);
      const services = [...bundle.serviceLabels.entries()].sort(
        ([leftId, leftLabel], [rightId, rightLabel]) =>
          compareStrings(leftLabel, rightLabel) ||
          compareStrings(leftId, rightId),
      );
      return {
        key,
        fromSegmentId: bundle.fromSegmentId,
        toSegmentId: bundle.toSegmentId,
        isSelf: bundle.fromSegmentId === bundle.toSegmentId,
        policyEdgeIds,
        flowIds,
        serviceIds: services.map(([serviceId]) => serviceId),
        serviceLabels: services.map(([, label]) => label),
        detailRows: sortConnectionDetails(bundle.detailRows.values()),
        connectionCount: policyEdgeIds.length + flowIds.length,
      };
    })
    .sort((left, right) => compareStrings(left.key, right.key));
}

/**
 * Connection details for flows that start at one projected host.
 *
 * The function reads only accepted scene flow groups. It never derives flow
 * semantics from graph edges. The rows use graph nodes only for their labels.
 */
export function buildOutgoingConnectionDetails(
  scene: TopologyScene,
  sourceHostId: string,
): TopologyConnectionDetailRow[] {
  return connectionDetailsForGroups(
    scene.flowGroups.filter(
      (group) => group.group.source_host_id === sourceHostId,
    ),
  );
}

function connectionDetailsForGroups(
  groups: readonly TopologyScene["flowGroups"][number][],
): TopologyConnectionDetailRow[] {
  const rows = new Map<string, TopologyConnectionDetailRow>();
  for (const group of groups) {
    for (const service of group.services) {
      addConnectionDetail(rows, {
        serviceId: service.id,
        serviceLabel: service.node.data.name,
        sourceHostId: group.source.id,
        sourceHostLabel: group.source.node.data.name,
        targetHostId: group.target.id,
        targetHostLabel: group.target.node.data.name,
      });
    }
  }
  return sortConnectionDetails(rows.values());
}

/**
 * Keeps one row for each visible label triple. Stable IDs choose the
 * representative when distinct projected entities have the same labels.
 */
function addConnectionDetail(
  rows: Map<string, TopologyConnectionDetailRow>,
  candidate: TopologyConnectionDetailRow,
): void {
  const key = connectionDetailDisplayKey(candidate);
  const existing = rows.get(key);
  if (!existing || compareConnectionDetailIds(candidate, existing) < 0) {
    rows.set(key, candidate);
  }
}

function connectionDetailDisplayKey(row: TopologyConnectionDetailRow): string {
  return JSON.stringify([
    row.serviceLabel,
    row.sourceHostLabel,
    row.targetHostLabel,
  ]);
}

function compareConnectionDetailIds(
  left: TopologyConnectionDetailRow,
  right: TopologyConnectionDetailRow,
): number {
  return (
    compareStrings(left.serviceId, right.serviceId) ||
    compareStrings(left.sourceHostId, right.sourceHostId) ||
    compareStrings(left.targetHostId, right.targetHostId)
  );
}

function sortConnectionDetails(
  rows: Iterable<TopologyConnectionDetailRow>,
): TopologyConnectionDetailRow[] {
  return [...rows].sort(
    (left, right) =>
      compareStrings(left.serviceLabel, right.serviceLabel) ||
      compareStrings(left.sourceHostLabel, right.sourceHostLabel) ||
      compareStrings(left.targetHostLabel, right.targetHostLabel) ||
      compareStrings(left.serviceId, right.serviceId) ||
      compareStrings(left.sourceHostId, right.sourceHostId) ||
      compareStrings(left.targetHostId, right.targetHostId),
  );
}

/** Locale-independent order, so projection output stays machine independent. */
function compareStrings(left: string, right: string): number {
  if (left === right) return 0;
  return left < right ? -1 : 1;
}
