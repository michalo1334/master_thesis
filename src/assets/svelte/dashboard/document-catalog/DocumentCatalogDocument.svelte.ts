import type { IconName } from "../types";
import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";

export class DocumentCatalogDocument extends WorkspaceDocumentBase {
  readonly kind = "document-catalog" as const;
  readonly id = "document-catalog";
  readonly title = "Documents";
  readonly icon = "squares-2x2" as const satisfies IconName;
}
