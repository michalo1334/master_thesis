import type { EChartsOption } from "echarts";

export interface KpiMetric {
  label: string;
  value: string;
  detail: string;
  tone: "neutral" | "positive" | "warning";
}

export interface ChartSpec {
  id: string;
  title: string;
  takeaway: string;
  ariaLabel: string;
  option: EChartsOption;
  height?: "standard" | "compact";
}
