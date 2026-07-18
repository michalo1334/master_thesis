import type { WorkspaceDocument } from "./document/WorkspaceDocument.svelte";
import type { LiveServer } from "./server";

export class DashboardController {
  private documents = $state<WorkspaceDocument[]>();

  public selectedDocumentId = $state<string | undefined>();

  constructor(private live: LiveServer) {}

  get activeDocument(): WorkspaceDocument | undefined {
    return this.documents?.find((each) => each.id == this.selectedDocumentId);
  }
}
