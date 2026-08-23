import { describe, expect, it } from "vitest";
import type { DocumentCatalogItem } from "../contract";
import { DocumentCatalogDocument } from "./DocumentCatalogDocument.svelte";

function item(id: string, graphId: string): DocumentCatalogItem {
  return {
    id,
    kind: "graph",
    graph_id: graphId,
    graph_revision_id: id,
    graph_title: graphId,
    revision_kind: "original",
    revision_number: 1,
    created_at: "2026-02-01T00:00:00Z",
  };
}

describe("DocumentCatalogDocument", () => {
  it("keeps a distinct relation snapshot until related mode is disabled", () => {
    const document = new DocumentCatalogDocument();
    const first = item("revision-a", "graph-a");
    const second = item("revision-b", "graph-a");
    const third = item("revision-c", "graph-b");
    document.rememberItems([first, third], []);
    document.setChosenKeys([first.id, third.id]);

    expect(document.showRelated()).toBe(true);
    expect(document.relatedGraphIds).toEqual(["graph-a", "graph-b"]);

    document.setChosenKeys([second.id]);
    document.rememberItems([], [first, second]);
    expect(document.relatedGraphIds).toEqual(["graph-a", "graph-b"]);
    expect(document.knownItems.get(second.id)).toBe(second);
    expect(document.chosenItems).toEqual([second]);

    document.hideRelated();
    expect(document.relatedGraphIds).toEqual([]);
    expect(document.relatedItems).toEqual([]);
    expect(document.chosenKeys).toEqual([second.id]);
    expect(document.toPersisted()).toEqual({
      kind: "document-catalog",
      ids: {},
      title: "Documents",
    });
  });
});
