import type {
  OptimizationReportErrorEvent,
  OptimizationReportReadyEvent,
  SimulationReportErrorEvent,
  SimulationReportReadyEvent,
} from "./contract";
import type { OptimizationReportDocument } from "./optimization-report/OptimizationReportDocument.svelte";
import type { SimulationReportDocument } from "./simulation-report/SimulationReportDocument.svelte";
import type { AsyncReportDocument } from "./workspace/WorkspaceDocument.svelte";

export type EventResult = "handled" | "error" | "ignored";

export interface ClientReportEvent {
  readonly documentId: string;
  handle(document: AsyncReportDocument): EventResult;
  visitSimulation(document: SimulationReportDocument): EventResult;
  visitOptimization(document: OptimizationReportDocument): EventResult;
}

abstract class ReportEventBase implements ClientReportEvent {
  abstract readonly documentId: string;
  abstract visitSimulation(document: SimulationReportDocument): EventResult;
  abstract visitOptimization(document: OptimizationReportDocument): EventResult;

  handle(document: AsyncReportDocument): EventResult {
    return document.accept(this);
  }
}

export class SimulationReportReady extends ReportEventBase {
  constructor(readonly payload: SimulationReportReadyEvent) {
    super();
  }

  get documentId(): string {
    return this.payload.document_id;
  }

  visitSimulation(document: SimulationReportDocument): EventResult {
    document.setReportData(this.payload.report);
    return "handled";
  }

  visitOptimization(_: OptimizationReportDocument): EventResult {
    return "ignored";
  }
}

export class SimulationReportError extends ReportEventBase {
  constructor(readonly payload: SimulationReportErrorEvent) {
    super();
  }

  get documentId(): string {
    return this.payload.document_id;
  }

  visitSimulation(document: SimulationReportDocument): EventResult {
    document.markError(this.payload.error);
    return "error";
  }

  visitOptimization(_: OptimizationReportDocument): EventResult {
    return "ignored";
  }
}

export class OptimizationReportReady extends ReportEventBase {
  constructor(readonly payload: OptimizationReportReadyEvent) {
    super();
  }

  get documentId(): string {
    return this.payload.document_id;
  }

  visitSimulation(_: SimulationReportDocument): EventResult {
    return "ignored";
  }

  visitOptimization(document: OptimizationReportDocument): EventResult {
    document.setReportData(this.payload.report);
    return "handled";
  }
}

export class OptimizationReportError extends ReportEventBase {
  constructor(readonly payload: OptimizationReportErrorEvent) {
    super();
  }

  get documentId(): string {
    return this.payload.document_id;
  }

  visitSimulation(_: SimulationReportDocument): EventResult {
    return "ignored";
  }

  visitOptimization(document: OptimizationReportDocument): EventResult {
    document.markError(this.payload.error);
    return "error";
  }
}
