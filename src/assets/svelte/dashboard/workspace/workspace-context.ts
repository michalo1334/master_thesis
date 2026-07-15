import { createContext } from "svelte";

interface WorkspaceDocument {
  id: string;
  title: () => string;
}

interface WorkspaceContext {
  registerDocument: (document: WorkspaceDocument) => () => void;
}

export const [getWorkspaceContext, setWorkspaceContext] = createContext<WorkspaceContext>();
