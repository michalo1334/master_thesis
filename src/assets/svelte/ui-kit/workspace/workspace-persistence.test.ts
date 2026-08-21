import { describe, expect, it } from "vitest";
import { isPersistedDocumentOfKind } from "./workspace-persistence";

describe("isPersistedDocumentOfKind", () => {
  it("accepts an exact descriptor with all required string IDs", () => {
    const value = {
      kind: "graph",
      ids: { graphId: "graph-1", folderId: "folder-1" },
      title: "Graph 1",
    };

    expect(
      isPersistedDocumentOfKind(value, "graph", ["graphId", "folderId"]),
    ).toBe(true);
  });

  it("rejects a wrong kind", () => {
    const value = {
      kind: "graph",
      ids: { graphId: "graph-1" },
      title: "Graph 1",
    };

    expect(isPersistedDocumentOfKind(value, "folder", ["graphId"])).toBe(false);
  });

  it("rejects a missing or non-string required ID", () => {
    const missing = {
      kind: "graph",
      ids: { graphId: "graph-1" },
      title: "Graph 1",
    };
    const nonString = {
      kind: "graph",
      ids: { graphId: 42 },
      title: "Graph 1",
    };

    expect(
      isPersistedDocumentOfKind(missing, "graph", ["graphId", "folderId"]),
    ).toBe(false);
    expect(isPersistedDocumentOfKind(nonString, "graph", ["graphId"])).toBe(
      false,
    );
  });
});
