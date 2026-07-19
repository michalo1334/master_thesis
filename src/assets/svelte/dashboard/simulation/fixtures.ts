import type { EChartsOption } from "echarts";
import type { ChartSpec, KpiMetric } from "./types";

const palette = ["#1769aa", "#4f8bc2", "#7daed6", "#e3a33e", "#b9574f"];
const axis = {
  axisLine: { lineStyle: { color: "#aeb8c5" } },
  axisLabel: { color: "#4d5a68", fontSize: 11 },
};
const tooltip = {
  trigger: "axis" as const,
  backgroundColor: "#172234",
  borderWidth: 0,
  textStyle: { color: "#ffffff" },
};

function option(value: EChartsOption): EChartsOption {
  return {
    animation: false,
    aria: { enabled: true },
    color: palette,
    textStyle: { fontFamily: "Segoe UI, Arial, sans-serif" },
    ...value,
  };
}

export const simulationKpis: readonly KpiMetric[] = [
  {
    label: "Simulation runs",
    value: "10,000",
    detail: "Monte Carlo trials completed",
    tone: "neutral",
  },
  {
    label: "Expected blast radius",
    value: "18.6 hosts",
    detail: "Median: 16 compromised hosts",
    tone: "warning",
  },
  {
    label: "Critical-asset exposure",
    value: "12.4%",
    detail: "Probability of one or more critical assets",
    tone: "warning",
  },
  {
    label: "Hybrid strategy reduction",
    value: "37.0%",
    detail: "Versus vulnerability-score baseline",
    tone: "positive",
  },
] as const;

export const distributionCharts: readonly ChartSpec[] = [
  {
    id: "cumulative-distribution",
    title: "Cumulative blast-radius distribution",
    takeaway:
      "Three quarters of simulated attacks compromise 24 or fewer hosts.",
    ariaLabel:
      "Area chart of the cumulative distribution of compromised hosts.",
    option: option({
      grid: { left: 48, right: 20, top: 20, bottom: 36 },
      tooltip: { ...tooltip, valueFormatter: (value) => `${value}%` },
      xAxis: {
        type: "category",
        name: "Compromised hosts",
        nameLocation: "middle",
        nameGap: 28,
        data: [0, 4, 8, 12, 16, 20, 24, 28, 32, 36],
        ...axis,
      },
      yAxis: {
        type: "value",
        name: "Runs (%)",
        min: 0,
        max: 100,
        ...axis,
        axisLabel: { ...axis.axisLabel, formatter: "{value}%" },
      },
      series: [
        {
          name: "Cumulative runs",
          type: "line",
          smooth: true,
          data: [1, 7, 19, 39, 58, 68, 76, 86, 94, 99],
          areaStyle: { color: "#b8d6ee" },
          lineStyle: { width: 2.5 },
        },
      ],
    }),
  },
  {
    id: "blast-radius-histogram",
    title: "Observed blast-radius distribution",
    takeaway:
      "Outcomes concentrate between 12 and 24 compromised hosts, with a smaller high-impact tail.",
    ariaLabel: "Histogram of compromised hosts across simulation runs.",
    option: option({
      grid: { left: 46, right: 18, top: 20, bottom: 34 },
      tooltip: { ...tooltip, valueFormatter: (value) => `${value} runs` },
      xAxis: {
        type: "category",
        data: [
          "0–4",
          "5–8",
          "9–12",
          "13–16",
          "17–20",
          "21–24",
          "25–28",
          "29–32",
          "33–36",
        ],
        ...axis,
      },
      yAxis: { type: "value", name: "Runs", ...axis },
      series: [
        {
          name: "Simulation runs",
          type: "bar",
          data: [215, 478, 1_046, 1_874, 2_142, 1_663, 1_145, 816, 621],
          barMaxWidth: 34,
          itemStyle: { borderRadius: [3, 3, 0, 0] },
        },
      ],
    }),
  },
  {
    id: "critical-zone-risk",
    title: "Critical-asset compromise probability",
    takeaway:
      "The data zone contributes the highest critical-asset exposure and should be the first containment priority.",
    ariaLabel:
      "Bar chart of critical asset compromise probability by network zone.",
    option: option({
      grid: { left: 48, right: 18, top: 20, bottom: 34 },
      tooltip: { ...tooltip, valueFormatter: (value) => `${value}%` },
      xAxis: {
        type: "category",
        data: ["DMZ", "Application", "Data", "Identity"],
        ...axis,
      },
      yAxis: {
        type: "value",
        name: "Probability",
        max: 30,
        ...axis,
        axisLabel: { ...axis.axisLabel, formatter: "{value}%" },
      },
      series: [
        {
          name: "Compromise probability",
          type: "bar",
          data: [8.1, 16.7, 24.6, 11.3],
          barMaxWidth: 42,
          itemStyle: { color: "#e3a33e", borderRadius: [3, 3, 0, 0] },
        },
      ],
    }),
  },
];

export const convergenceCharts: readonly ChartSpec[] = [
  {
    id: "mean-convergence",
    title: "Monte Carlo convergence",
    takeaway:
      "The expected blast radius stabilizes near 18.6 hosts after about 6,000 runs.",
    ariaLabel:
      "Line chart showing mean blast radius as Monte Carlo runs increase.",
    option: option({
      grid: { left: 48, right: 20, top: 26, bottom: 38 },
      legend: { top: 0, selectedMode: true, textStyle: { color: "#4d5a68" } },
      tooltip,
      xAxis: {
        type: "category",
        name: "Completed runs",
        nameLocation: "middle",
        nameGap: 28,
        data: [500, 1_000, 2_000, 3_000, 4_000, 6_000, 8_000, 10_000],
        ...axis,
      },
      yAxis: { type: "value", name: "Mean hosts", min: 16, max: 21, ...axis },
      series: [
        {
          name: "Mean blast radius",
          type: "line",
          data: [20.3, 19.5, 19.0, 18.8, 18.7, 18.6, 18.6, 18.6],
          smooth: true,
          lineStyle: { width: 2.5 },
        },
        {
          name: "95% confidence band",
          type: "line",
          data: [17.1, 17.4, 17.7, 17.9, 18.0, 18.2, 18.3, 18.3],
          smooth: true,
          lineStyle: { type: "dashed" },
          symbol: "none",
        },
      ],
    }),
  },
];

export const strategyCharts: readonly ChartSpec[] = [
  {
    id: "strategy-comparison",
    title: "Defense-strategy comparison",
    takeaway:
      "The hybrid strategy lowers the expected blast radius most consistently across tested attack profiles.",
    ariaLabel:
      "Grouped bar chart comparing expected blast radius for four defense strategies.",
    option: option({
      grid: { left: 48, right: 18, top: 28, bottom: 52 },
      legend: { top: 0, selectedMode: true, textStyle: { color: "#4d5a68" } },
      tooltip,
      xAxis: {
        type: "category",
        data: [
          "Vulnerability score",
          "Topology score",
          "Simulation-informed",
          "Hybrid",
        ],
        axisLabel: { interval: 0, rotate: 20, color: "#4d5a68", fontSize: 10 },
        axisLine: axis.axisLine,
      },
      yAxis: { type: "value", name: "Expected hosts", ...axis },
      series: [
        {
          name: "Credential theft",
          type: "bar",
          data: [24.3, 22.1, 18.8, 15.2],
          barMaxWidth: 28,
        },
        {
          name: "Internet-facing exploit",
          type: "bar",
          data: [21.4, 20.8, 17.5, 14.1],
          barMaxWidth: 28,
        },
      ],
    }),
  },
  {
    id: "defense-mix",
    title: "Defense actions by strategy",
    takeaway:
      "Hybrid defense spends its limited budget on both patches and segmentation rather than concentrating on one control type.",
    ariaLabel:
      "Stacked bar chart comparing patching and segmentation actions by defense strategy.",
    option: option({
      grid: { left: 48, right: 18, top: 28, bottom: 52 },
      legend: { top: 0, selectedMode: true, textStyle: { color: "#4d5a68" } },
      tooltip,
      xAxis: {
        type: "category",
        data: [
          "Vulnerability score",
          "Topology score",
          "Simulation-informed",
          "Hybrid",
        ],
        axisLabel: { interval: 0, rotate: 20, color: "#4d5a68", fontSize: 10 },
        axisLine: axis.axisLine,
      },
      yAxis: { type: "value", name: "Defense actions", ...axis },
      series: [
        {
          name: "Patches",
          type: "bar",
          stack: "actions",
          data: [14, 4, 11, 9],
          barMaxWidth: 38,
        },
        {
          name: "Segmentation rules",
          type: "bar",
          stack: "actions",
          data: [1, 12, 5, 8],
          barMaxWidth: 38,
          itemStyle: { borderRadius: [3, 3, 0, 0] },
        },
      ],
    }),
  },
  {
    id: "hybrid-budget-allocation",
    title: "Hybrid-defense budget allocation",
    takeaway:
      "Segmentation uses the largest share of the hybrid budget because it reduces lateral movement across high-risk boundaries.",
    ariaLabel: "Donut chart showing hybrid defense budget allocation.",
    option: option({
      tooltip: {
        trigger: "item",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: { color: "#ffffff" },
        valueFormatter: (value) => `${value}%`,
      },
      legend: {
        bottom: 0,
        selectedMode: true,
        textStyle: { color: "#4d5a68" },
      },
      series: [
        {
          name: "Budget allocation",
          type: "pie",
          radius: ["48%", "72%"],
          center: ["50%", "43%"],
          avoidLabelOverlap: true,
          label: { show: false },
          data: [
            { value: 42, name: "Segmentation" },
            { value: 35, name: "Patching" },
            { value: 23, name: "Identity hardening" },
          ],
        },
      ],
    }),
  },
];

export const sensitivityCharts: readonly ChartSpec[] = [
  {
    id: "exposure-sensitivity",
    title: "Exposure and compromise sensitivity",
    takeaway:
      "Attack paths with more exposed vulnerabilities have a materially higher chance of crossing into critical zones.",
    ariaLabel:
      "Scatter chart of exposed vulnerabilities and critical zone compromise probability.",
    option: option({
      grid: { left: 48, right: 18, top: 20, bottom: 38 },
      tooltip: {
        trigger: "item",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: { color: "#ffffff" },
      },
      xAxis: {
        type: "value",
        name: "Exposed vulnerabilities",
        nameLocation: "middle",
        nameGap: 28,
        ...axis,
      },
      yAxis: {
        type: "value",
        name: "Critical-zone probability",
        max: 40,
        ...axis,
        axisLabel: { ...axis.axisLabel, formatter: "{value}%" },
      },
      series: [
        {
          name: "Scenarios",
          type: "scatter",
          symbolSize: 11,
          data: [
            [3, 4],
            [5, 7],
            [6, 9],
            [8, 13],
            [9, 15],
            [11, 18],
            [12, 21],
            [14, 26],
            [16, 31],
            [18, 35],
          ],
          itemStyle: { color: "#1769aa" },
        },
      ],
    }),
  },
  {
    id: "topology-variability",
    title: "Blast-radius variability by topology",
    takeaway:
      "Dense topologies produce the widest range of outcomes, making segmentation especially valuable in those networks.",
    ariaLabel: "Box plot of blast radius by network topology.",
    option: option({
      grid: { left: 48, right: 18, top: 20, bottom: 34 },
      tooltip: {
        trigger: "item",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: { color: "#ffffff" },
      },
      xAxis: {
        type: "category",
        data: ["Layered", "Mesh", "Hub-spoke", "Dense"],
        ...axis,
      },
      yAxis: { type: "value", name: "Compromised hosts", ...axis },
      series: [
        {
          name: "Blast radius",
          type: "boxplot",
          data: [
            [5, 10, 14, 18, 26],
            [8, 15, 20, 27, 38],
            [4, 8, 12, 16, 22],
            [12, 21, 29, 36, 51],
          ],
          itemStyle: { color: "#7daed6", borderColor: "#1769aa" },
        },
      ],
    }),
  },
  {
    id: "run-density-heatmap",
    title: "Simulation stability by run count and density",
    takeaway:
      "Sparse networks stabilize with fewer runs; dense topologies need at least 6,000 runs before estimates become reliable.",
    ariaLabel:
      "Heatmap of estimate stability by simulation run count and topology density.",
    option: option({
      grid: { left: 58, right: 20, top: 20, bottom: 40 },
      tooltip: {
        position: "top",
        backgroundColor: "#172234",
        borderWidth: 0,
        textStyle: { color: "#ffffff" },
        valueFormatter: (value) => `${value}% stability`,
      },
      xAxis: {
        type: "category",
        name: "Simulation runs",
        nameLocation: "middle",
        nameGap: 28,
        data: ["1k", "2k", "4k", "6k", "8k", "10k"],
        ...axis,
      },
      yAxis: {
        type: "category",
        name: "Topology",
        nameLocation: "middle",
        nameGap: 42,
        data: ["Sparse", "Moderate", "Dense"],
        ...axis,
      },
      visualMap: {
        min: 60,
        max: 100,
        calculable: false,
        orient: "horizontal",
        left: "center",
        bottom: 0,
        inRange: { color: ["#edf1f5", "#b8d6ee", "#1769aa"] },
        textStyle: { color: "#4d5a68" },
      },
      series: [
        {
          name: "Estimate stability",
          type: "heatmap",
          data: [
            [0, 0, 76],
            [1, 0, 86],
            [2, 0, 93],
            [3, 0, 96],
            [4, 0, 98],
            [5, 0, 99],
            [0, 1, 68],
            [1, 1, 78],
            [2, 1, 88],
            [3, 1, 93],
            [4, 1, 96],
            [5, 1, 98],
            [0, 2, 61],
            [1, 2, 69],
            [2, 2, 80],
            [3, 2, 88],
            [4, 2, 93],
            [5, 2, 96],
          ],
        },
      ],
    }),
  },
];
