export { default as Workspace } from "./Workspace.svelte";
export { default as DocumentOutline } from "./DocumentOutline.svelte";
export {
  UiWorkspaceDocument,
  UiWorkspaceDocument as WorkspaceDocumentBase,
} from "./WorkspaceDocument.svelte";
export {
  GenericWorkspaceModel,
  type DocumentFactory,
  type DocumentFactoryRegistry,
  type WorkspacePersistenceConfig,
} from "./WorkspaceModel.svelte";
export {
  createWorkspaceEnvelope,
  persistedDocumentKey,
  readWorkspaceEnvelope,
  writeWorkspaceEnvelope,
  type PersistedWorkspaceDocument,
  type StorageLike,
  type WorkspaceEnvelope,
} from "./workspace-persistence";
export {
  buildOutline,
  type OutlineDrag,
  type OutlineDrop,
  type OutlineGroup,
  type OutlineNode,
  type OutlineRow,
} from "./outline";
export type { InspectorContext, InspectorRegistry } from "./inspector-registry";
