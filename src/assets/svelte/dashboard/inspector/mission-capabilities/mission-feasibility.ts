export interface RequiredFlow {
  source_segment_id: string;
  target_service_id: string;
}

type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord | undefined {
  return value && typeof value === "object"
    ? (value as UnknownRecord)
    : undefined;
}

function valueAt(source: unknown, ...keys: string[]): unknown {
  const sourceRecord = record(source);
  for (const key of keys) {
    if (sourceRecord?.[key] !== undefined) return sourceRecord[key];
  }
}

export function requiredFlows(data: unknown): RequiredFlow[] {
  const flows = valueAt(data, "required_flows");
  return Array.isArray(flows)
    ? flows.flatMap((flow) => {
        const sourceSegmentId = valueAt(flow, "source_segment_id");
        const targetServiceId = valueAt(flow, "target_service_id");
        return typeof sourceSegmentId === "string" &&
          typeof targetServiceId === "string"
          ? [
              {
                source_segment_id: sourceSegmentId,
                target_service_id: targetServiceId,
              },
            ]
          : [];
      })
    : [];
}
