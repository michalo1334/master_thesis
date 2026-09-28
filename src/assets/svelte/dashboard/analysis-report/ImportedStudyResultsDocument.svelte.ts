import type { EvaluationAnalysis } from "../../contracts.generated/dashboard/evaluation";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";

export class ImportedStudyResultsDocument extends WorkspaceDocumentBase {
  readonly kind = "imported-study-results" as const;
  readonly documentLabel = "Study results";
  readonly icon = "simulation-report" as const satisfies string;
  readonly id = crypto.randomUUID();
  readonly title = "Imported study results";
  readonly analysis: EvaluationAnalysis;

  constructor(analysis: EvaluationAnalysis) {
    super();
    this.analysis = analysis;
  }
}
