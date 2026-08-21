import { WorkspaceDocumentBase } from "../workspace/WorkspaceDocument.svelte";
import type { DashboardRecoveryContext } from "../workspace/recovery-context";
import type { PersistedWorkspaceDocument } from "../../ui-kit/workspace/workspace-persistence";

export class RunsDocument extends WorkspaceDocumentBase {
  readonly kind = "runs" as const;
  readonly documentLabel = "Table";
  readonly id = "runs";
  readonly title = "Runs";
  readonly icon = "play" as const satisfies string;
  static readonly createOption = {
    id: "runs",
    label: "Runs",
    icon: "play" as const,
  };

  static fromPersisted(
    _data: unknown,
    _context: DashboardRecoveryContext,
  ): RunsDocument {
    return new RunsDocument();
  }

  toPersisted(): PersistedWorkspaceDocument | undefined {
    return { kind: "runs", ids: {}, title: this.title };
  }
}
