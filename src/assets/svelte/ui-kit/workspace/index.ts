export { default as Workspace } from "./Workspace.svelte";
export { default as DocumentOutline } from "./DocumentOutline.svelte";
export {
  UiWorkspaceDocument,
  UiWorkspaceDocument as WorkspaceDocumentBase,
} from "./WorkspaceDocument.svelte";
export { GenericWorkspaceModel } from "./WorkspaceModel.svelte";
export {
  buildOutline,
  type OutlineGroup,
  type OutlineNode,
  type OutlineRow,
} from "./outline";
export type { InspectorContext, InspectorRegistry } from "./inspector-registry";
