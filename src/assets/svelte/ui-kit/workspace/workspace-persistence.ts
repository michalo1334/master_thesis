export interface PersistedWorkspaceDocument {
  kind: string;
  ids: Record<string, string>;
  title: string;
}

export interface WorkspaceEnvelope<State> {
  version: number;
  state: State;
  documents: PersistedWorkspaceDocument[];
  selectedDocumentKey?: string;
}

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** Stable, durable key for a persisted document, used to track the selected tab. */
export function persistedDocumentKey(
  document: PersistedWorkspaceDocument,
): string {
  const ids = Object.entries(document.ids)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}:${value}`)
    .join(",");
  return `${document.kind}:${ids}`;
}

export function createWorkspaceEnvelope<State>(
  input: Omit<WorkspaceEnvelope<State>, "version">,
  version: number,
): WorkspaceEnvelope<State> {
  return { version, ...input };
}

export function readWorkspaceEnvelope<State>(
  storageKey: string,
  validate: (value: unknown) => value is State,
  storage: StorageLike | undefined = browserStorage(),
): WorkspaceEnvelope<State> | undefined {
  if (!storage) return undefined;
  try {
    const stored = storage.getItem(storageKey);
    if (!stored) return undefined;
    const parsed: unknown = JSON.parse(stored);
    return isWorkspaceEnvelope(parsed, validate) ? parsed : undefined;
  } catch {
    return undefined;
  }
}

export function writeWorkspaceEnvelope<State>(
  storageKey: string,
  envelope: WorkspaceEnvelope<State>,
  storage: StorageLike | undefined = browserStorage(),
): boolean {
  if (!storage) return false;
  try {
    storage.setItem(storageKey, JSON.stringify(envelope));
    return true;
  } catch {
    return false;
  }
}

function browserStorage(): StorageLike | undefined {
  if (typeof window === "undefined") return undefined;
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

function isWorkspaceEnvelope<State>(
  value: unknown,
  validate: (value: unknown) => value is State,
): value is WorkspaceEnvelope<State> {
  if (!isRecord(value) || typeof value.version !== "number") return false;
  if (!validate(value.state)) return false;
  if (!Array.isArray(value.documents)) return false;
  if (
    value.selectedDocumentKey !== undefined &&
    typeof value.selectedDocumentKey !== "string"
  ) {
    return false;
  }
  return value.documents.every(isPersistedWorkspaceDocument);
}

function isPersistedWorkspaceDocument(
  value: unknown,
): value is PersistedWorkspaceDocument {
  return (
    isRecord(value) &&
    typeof value.kind === "string" &&
    isRecord(value.ids) &&
    Object.values(value.ids).every((id) => typeof id === "string") &&
    typeof value.title === "string"
  );
}

export function isPersistedDocumentOfKind<Ids extends Record<string, string>>(
  value: unknown,
  kind: string,
  idKeys: (keyof Ids)[],
): value is PersistedWorkspaceDocument & { ids: Ids } {
  if (!isRecord(value)) return false;
  if (value.kind !== kind) return false;
  if (!isRecord(value.ids)) return false;
  for (const key of idKeys) {
    if (typeof value.ids[key as string] !== "string") return false;
  }
  return typeof value.title === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
