import type { PersistedWorkspaceDocument } from "./workspace-persistence";

export abstract class UiWorkspaceDocument {
  abstract readonly id: string;
  abstract readonly kind: string;
  abstract readonly title: string;
  abstract readonly icon: string;
  abstract readonly documentLabel: string;

  protected persistedData: unknown;

  canClose(): boolean {
    return true;
  }

  isReportDocument(): boolean {
    return false;
  }

  /** Serialize this document for persistence. Return undefined to skip it. */
  toPersisted(): PersistedWorkspaceDocument | undefined {
    return undefined;
  }

  /** Recover this document from its persisted snapshot on activation. */
  recover(_context: unknown): void {}

  /** Whether this document is a lazy stub awaiting recovery. */
  needsRecovery(): boolean {
    return this.persistedData !== undefined;
  }

  /** Mark this document as a restored stub carrying persisted data. */
  setPersisted(data: unknown): void {
    this.persistedData = data;
  }
}
