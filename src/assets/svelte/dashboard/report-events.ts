import type {
  OptimizationReportErrorEvent,
  OptimizationReportReadyEvent,
  SimulationReportErrorEvent,
  SimulationReportReadyEvent,
} from "./contract";

export type ReportKind = "simulation" | "optimization";

export type ReportReadyPayloadMap = {
  simulation: SimulationReportReadyEvent;
  optimization: OptimizationReportReadyEvent;
};

export type ReportErrorPayloadMap = {
  simulation: SimulationReportErrorEvent;
  optimization: OptimizationReportErrorEvent;
};

export type ReportDataMap = {
  [Kind in ReportKind]: ReportReadyPayloadMap[Kind]["report"];
};

export type ReportReadyEventType<Kind extends ReportKind = ReportKind> =
  Kind extends ReportKind
    ? { reportKind: Kind; payload: ReportReadyPayloadMap[Kind] }
    : never;

export type ReportErrorEventType<Kind extends ReportKind = ReportKind> =
  Kind extends ReportKind
    ? { reportKind: Kind; payload: ReportErrorPayloadMap[Kind] }
    : never;
