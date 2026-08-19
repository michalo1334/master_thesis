export abstract class UiWorkspaceDocument {
  abstract readonly id: string;
  abstract readonly kind: string;
  abstract readonly title: string;
  abstract readonly icon: string;
  abstract readonly documentLabel: string;

  canClose(): boolean {
    return true;
  }

  isReportDocument(): boolean {
    return false;
  }
}
