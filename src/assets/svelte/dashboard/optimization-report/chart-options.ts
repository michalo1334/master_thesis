import type { OptimizationAction } from "../../contracts.generated/dashboard/optimization";
import type { EChartsOption } from "echarts";
const colors = {
  accent: "#1769d2",
  grid: "#e2e7ed",
  text: "#4e5b6e",
};

export function cvssOptions(
  actions: readonly OptimizationAction[],
): EChartsOption {
  const scoredActions = actions.filter(
    (
      action,
    ): action is OptimizationAction & {
      cvss_score: number;
    } => action.cvss_score != null,
  );

  return {
    aria: { enabled: true },
    textStyle: { color: colors.text },
    grid: { top: 16, right: 20, bottom: 36, left: 112 },
    tooltip: { trigger: "axis" },
    xAxis: {
      type: "value",
      name: "CVSS score",
      nameLocation: "middle",
      nameGap: 28,
      min: 0,
      max: 10,
      axisLabel: { color: colors.text },
      splitLine: { lineStyle: { color: colors.grid } },
    },
    yAxis: {
      type: "category",
      data: scoredActions.map((action) => action.label),
      axisLabel: { color: colors.text, overflow: "truncate", width: 96 },
    },
    series: [
      {
        type: "bar",
        data: scoredActions.map((action) => action.cvss_score),
        itemStyle: { color: colors.accent },
      },
    ],
  };
}
