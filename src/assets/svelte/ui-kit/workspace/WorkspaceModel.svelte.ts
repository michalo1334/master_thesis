import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";

export class GenericWorkspaceModel<D extends UiWorkspaceDocument> {
  documents = $state<D[]>([]);
  selectedDocumentId = $state<string | undefined>();

  get activeDocument(): D | undefined {
    return this.documents.find((d) => d.id === this.selectedDocumentId);
  }

  selectDocument(id: string): void {
    this.selectedDocumentId = this.documents.find((d) => d.id === id)?.id;
  }

  reorderDocuments(draggedId: string, targetId: string): void {
    const draggedIndex = this.documents.findIndex(
      (document) => document.id === draggedId,
    );
    const targetIndex = this.documents.findIndex(
      (document) => document.id === targetId,
    );
    if (draggedIndex < 0 || targetIndex < 0 || draggedId === targetId) {
      return;
    }

    const documents = [...this.documents];
    const [dragged] = documents.splice(draggedIndex, 1);
    documents.splice(targetIndex, 0, dragged!);
    this.documents = documents;
  }

  canCloseDocument(document: D): boolean {
    return document.canClose();
  }

  closeDocument(id: string): void {
    const currentIdx = this.documents.findIndex(
      (document) => document.id === id,
    );
    if (currentIdx === -1) return;
    if (!this.canCloseDocument(this.documents[currentIdx])) return;

    this.documents = this.documents.filter((d) => d.id !== id);

    if (this.selectedDocumentId === id) {
      if (this.documents.length === 0) {
        this.selectedDocumentId = undefined;
      } else {
        const nextIdx = currentIdx > 0 ? currentIdx - 1 : 0;
        this.selectedDocumentId = this.documents[nextIdx]?.id;
      }
    }
  }
}
