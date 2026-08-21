import type { UiWorkspaceDocument } from "./WorkspaceDocument.svelte";
import {
  createWorkspaceEnvelope,
  persistedDocumentKey,
  type WorkspaceEnvelope,
} from "./workspace-persistence";

export type DocumentFactory<D, Ctx> = (
  data: unknown,
  context: Ctx,
) => D | undefined;

export type DocumentFactoryRegistry<D, Ctx> = ReadonlyMap<
  string,
  DocumentFactory<D, Ctx>
>;

export interface WorkspacePersistenceConfig<D, State, Ctx> {
  version: number;
  snapshotState(): State;
  restoreState(state: State): void;
  validateState(value: unknown): value is State;
  documentFactory: DocumentFactoryRegistry<D, Ctx>;
  recoveryContext: Ctx;
}

export class GenericWorkspaceModel<
  D extends UiWorkspaceDocument,
  State = unknown,
  Ctx = unknown,
> {
  documents = $state<D[]>([]);
  selectedDocumentId = $state<string | undefined>();

  private persistence?: WorkspacePersistenceConfig<D, State, Ctx>;

  get activeDocument(): D | undefined {
    return this.documents.find((d) => d.id === this.selectedDocumentId);
  }

  configurePersistence(
    config: WorkspacePersistenceConfig<D, State, Ctx>,
  ): void {
    this.persistence = config;
  }

  selectDocument(id: string): void {
    this.selectedDocumentId = this.documents.find((d) => d.id === id)?.id;
    this.recoverActiveDocument();
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
    this.recoverActiveDocument();
  }

  snapshot(): WorkspaceEnvelope<State> | undefined {
    const persistence = this.persistence;
    if (!persistence) return undefined;

    const documents = this.documents.flatMap((document) => {
      const persisted = document.toPersisted();
      return persisted ? [persisted] : [];
    });
    const selected = this.activeDocument?.toPersisted();

    return createWorkspaceEnvelope(
      {
        state: persistence.snapshotState(),
        documents,
        ...(selected &&
        documents.some(
          (document) =>
            persistedDocumentKey(document) === persistedDocumentKey(selected),
        )
          ? { selectedDocumentKey: persistedDocumentKey(selected) }
          : {}),
      },
      persistence.version,
    );
  }

  restore(envelope: WorkspaceEnvelope<State> | undefined): void {
    const persistence = this.persistence;
    if (!envelope || !persistence) return;
    if (envelope.version !== persistence.version) return;
    if (!persistence.validateState(envelope.state)) return;

    persistence.restoreState(envelope.state);

    this.documents = [];
    this.selectedDocumentId = undefined;

    for (const persisted of envelope.documents) {
      const factory = persistence.documentFactory.get(persisted.kind);
      if (!factory) continue;
      const document = factory(persisted, persistence.recoveryContext);
      if (!document) continue;
      this.documents.push(document);
      if (persistedDocumentKey(persisted) === envelope.selectedDocumentKey) {
        this.selectedDocumentId = document.id;
      }
    }
    this.recoverActiveDocument();
  }

  protected recoverActiveDocument(): void {
    const persistence = this.persistence;
    const document = this.activeDocument;
    if (!persistence || !document || !document.needsRecovery()) return;
    document.recover(persistence.recoveryContext);
  }
}
