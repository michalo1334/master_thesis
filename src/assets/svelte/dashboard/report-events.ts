import type {
  EvaluationReportErrorEvent,
  EvaluationReportReadyEvent,
  OptimizationReportErrorEvent,
  OptimizationReportReadyEvent,
  SimulationReportErrorEvent,
  SimulationReportReadyEvent,
} from "./contract";

export type ReportKind = "simulation" | "optimization" | "evaluation";

export type ReportReadyPayloadMap = {
  simulation: SimulationReportReadyEvent;
  optimization: OptimizationReportReadyEvent;
  evaluation: EvaluationReportReadyEvent;
};

export type ReportErrorPayloadMap = {
  simulation: SimulationReportErrorEvent;
  optimization: OptimizationReportErrorEvent;
  evaluation: EvaluationReportErrorEvent;
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
