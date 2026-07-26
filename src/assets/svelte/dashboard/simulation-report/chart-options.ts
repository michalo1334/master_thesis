import type { EChartsOption } from "echarts";
import type {
  SimulationReportActionSuccess,
  SimulationReportCdfPoint,
  SimulationReportConvergencePoint,
  SimulationReportHistogramBucket,
} from "../../contracts.generated";

const colors = {
  accent: "#1769d2",
  positive: "#39825a",
  warning: "#d18b21",
  text: "#4e5b6e",
  grid: "#e2e7ed",
};

const baseOption = (): EChartsOption => ({
  aria: { enabled: true },
  textStyle: { color: colors.text },
  grid: { top: 16, right: 20, bottom: 36, left: 48 },
  tooltip: { trigger: "axis" },
});

export function histogramOptions(
  buckets: readonly SimulationReportHistogramBucket[],
): EChartsOption {
  return {
    ...baseOption(),
    xAxis: {
      type: "category",
      name: "Compromised hosts",
      nameLocation: "middle",
      nameGap: 28,
      data: buckets.map(
        ({ lower_bound, upper_bound }) => `${lower_bound}–${upper_bound}`,
      ),
      axisLabel: { color: colors.text },
    },
    yAxis: {
      type: "value",
      name: "Runs",
      minInterval: 1,
      splitLine: { lineStyle: { color: colors.grid } },
      axisLabel: { color: colors.text },
    },
    series: [
      {
        type: "bar",
        data: buckets.map(({ count }) => count),
        itemStyle: { color: colors.accent },
      },
    ],
  };
}

export function cdfOptions(
  points: readonly SimulationReportCdfPoint[],
): EChartsOption {
  return {
    ...baseOption(),
    xAxis: {
      type: "value",
      name: "Compromised hosts",
      nameLocation: "middle",
      nameGap: 28,
      axisLabel: { color: colors.text },
    },
    yAxis: {
      type: "value",
      name: "Cumulative probability",
      min: 0,
      max: 1,
      axisLabel: {
        color: colors.text,
        formatter: (value: number) => `${value * 100}%`,
      },
      splitLine: { lineStyle: { color: colors.grid } },
    },
    series: [
      {
        type: "line",
        data: points.map(({ compromised_hosts, cumulative_probability }) => [
          compromised_hosts,
          cumulative_probability,
        ]),
        showSymbol: false,
        lineStyle: { color: colors.accent, width: 2 },
      },
    ],
  };
}

export function convergenceOptions(
  points: readonly SimulationReportConvergencePoint[],
): EChartsOption {
  return {
    ...baseOption(),
    xAxis: {
      type: "value",
      name: "Run",
      nameLocation: "middle",
      nameGap: 28,
      minInterval: 1,
      axisLabel: { color: colors.text },
    },
    yAxis: {
      type: "value",
      name: "Mean blast radius",
      axisLabel: { color: colors.text },
      splitLine: { lineStyle: { color: colors.grid } },
    },
    series: [
      {
        type: "line",
        data: points.map(({ run, mean_blast_radius }) => [
          run,
          mean_blast_radius,
        ]),
        showSymbol: false,
        lineStyle: { color: colors.positive, width: 2 },
      },
    ],
  };
}

export function actionSuccessOptions(
  actions: readonly SimulationReportActionSuccess[],
): EChartsOption {
  return {
    ...baseOption(),
    legend: { data: ["Attempts", "Successful actions"] },
    xAxis: {
      type: "category",
      data: actions.map(({ action_type }) => action_type),
      axisLabel: { color: colors.text },
    },
    yAxis: {
      type: "value",
      name: "Actions",
      minInterval: 1,
      axisLabel: { color: colors.text },
      splitLine: { lineStyle: { color: colors.grid } },
    },
    series: [
      {
        name: "Attempts",
        type: "bar",
        data: actions.map(({ attempts }) => attempts),
        itemStyle: { color: colors.warning },
      },
      {
        name: "Successful actions",
        type: "bar",
        data: actions.map(({ successes }) => successes),
        itemStyle: { color: colors.positive },
      },
    ],
  };
}
