import type { FieldKind } from "../../../contracts.generated/graph/data";

export type SelectionCustomField = "requiredFlows";

interface SelectionPresentation {
  labels?: Readonly<Record<string, string>>;
  hidden?: readonly string[];
  custom?: Readonly<Record<string, SelectionCustomField>>;
}

const presentation: Readonly<Record<string, SelectionPresentation>> = {
  NetworkSegment: { labels: { cidr: "CIDR" } },
  MissionCapability: {
    labels: {
      impact_weight: "Impact weight",
      min_operational_support: "Minimum operational support",
    },
    custom: { required_flows: "requiredFlows" },
  },
};

export function fieldPresentation(
  type: string,
  path: readonly string[],
  kind: FieldKind,
): { label: string; hidden: boolean; custom?: SelectionCustomField } {
  const key = path.join(".");
  const config = presentation[type];
  return {
    label: config?.labels?.[key] ?? path.join(" · ").replaceAll("_", " "),
    hidden: kind === "list" || config?.hidden?.includes(key) === true,
    custom: config?.custom?.[key],
  };
}
