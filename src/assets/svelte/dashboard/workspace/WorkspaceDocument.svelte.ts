import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";

export type WorkspaceDocument =
  EditableGraphDocument | SimulationReportDocument;
