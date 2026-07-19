import type { DocumentBase } from "../workspace/WorkspaceDocument.svelte";

export class SimulationReportDocument implements DocumentBase {
  readonly kind = "simulation-report" as const;
  readonly id: string;
  readonly title: string;

  /** null means simulation has not yet produced a result */
  result = $state<unknown>(null);

  constructor(title: string) {
    this.id = crypto.randomUUID();
    this.title = title;
  }
}
