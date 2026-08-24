import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import DocumentCatalog from "./DocumentCatalog.svelte";
import { DocumentCatalogDocument } from "./DocumentCatalogDocument.svelte";
import type { DashboardApi, DocumentCatalogQuery } from "../dashboard-api";
import type {
  DocumentCatalogItem,
  FetchDocumentCatalogReply,
} from "../contract";

const items: DocumentCatalogItem[] = [
  {
    id: "graph-1",
    kind: "graph",
    graph_id: "graph-1",
    graph_revision_id: "revision-1",
    graph_title: "Gateway",
    revision_kind: "original",
    revision_number: 1,
    created_at: "2026-01-01T00:00:00Z",
  },
  {
    id: "optimization-1",
    kind: "optimization_report",
    graph_id: "graph-2",
    graph_revision_id: "revision-2",
    graph_title: "Branch",
    revision_kind: "optimization",
    revision_number: 4,
    output_revision_kind: "optimization",
    output_revision_number: 23,
    strategy: "greedy",
    created_at: "2026-01-03T00:00:00Z",
  },
];

const analysisItem: DocumentCatalogItem = {
  ...items[0],
  id: "analysis-1",
  kind: "analysis_report",
  manifest_id: "manifest-1",
  manifest_title: "Evaluation manifest",
};

function reply(
  catalogItems: DocumentCatalogItem[] = items,
  total_count = catalogItems.length,
  related_items: DocumentCatalogItem[] = [],
): FetchDocumentCatalogReply {
  return {
    items: catalogItems,
    related_items,
    total_count,
    filter_options: {
      types: ["graph", "optimization_report", "analysis_report"],
      graphs: [
        { id: "graph-1", title: "Gateway" },
        { id: "graph-2", title: "Branch" },
      ],
      strategies: ["greedy"],
      revision_kinds: ["original", "optimization"],
    },
  };
}

function renderCatalog(api: DashboardApi, onOpen = vi.fn()) {
  return render(DocumentCatalog, {
    props: {
      document: new DocumentCatalogDocument(onOpen),
      api,
    },
  });
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
} {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => (resolve = done));
  return { promise, resolve };
}

afterEach(cleanup);

describe("DocumentCatalog", () => {
  it("shows, filters, selects, and opens analysis reports", async () => {
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue(reply([analysisItem])),
    } as unknown as DashboardApi;
    const onOpen = vi.fn().mockResolvedValue(true);

    renderCatalog(api, onOpen);
    await waitFor(() =>
      expect(screen.getByText("Analysis report")).toBeInTheDocument(),
    );
    await fireEvent.click(screen.getByRole("button", { name: /Type filter/ }));
    expect(
      screen.getByRole("checkbox", { name: "Analysis report" }),
    ).toBeInTheDocument();
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select analysis-1" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Open selected (1)" }),
    );
    await waitFor(() => expect(onOpen).toHaveBeenCalledWith(analysisItem));
  });

  it("keeps selected documents from visited pages", async () => {
    const secondPage = [
      {
        ...items[1],
        id: "optimization-2",
      },
    ];
    const api = {
      fetchDocumentCatalog: vi
        .fn()
        .mockResolvedValueOnce(reply([items[0]], 9))
        .mockResolvedValueOnce(reply(secondPage, 9)),
    } as unknown as DashboardApi;
    const onOpen = vi.fn().mockResolvedValue(true);

    renderCatalog(api, onOpen);
    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "Select graph-1" }),
      ).toBeInTheDocument(),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select graph-1" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Page 2" }));
    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "Select optimization-2" }),
      ).toBeInTheDocument(),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select optimization-2" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Open selected (2)" }),
    );

    await waitFor(() => expect(onOpen).toHaveBeenCalledTimes(2));
    expect(onOpen).toHaveBeenNthCalledWith(1, items[0]);
    expect(onOpen).toHaveBeenNthCalledWith(2, secondPage[0]);
  });

  it("refetches the final page when the current page becomes empty", async () => {
    const fetchDocumentCatalog = vi
      .fn()
      .mockResolvedValueOnce(reply([items[0]], 9))
      .mockResolvedValueOnce(reply([], 1))
      .mockResolvedValueOnce(reply([items[0]], 1));
    const api = { fetchDocumentCatalog } as unknown as DashboardApi;

    renderCatalog(api);
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Page 2" }),
      ).toBeInTheDocument(),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Page 2" }));

    await waitFor(() => expect(fetchDocumentCatalog).toHaveBeenCalledTimes(3));
    expect(fetchDocumentCatalog).toHaveBeenLastCalledWith({
      search: "",
      types: [],
      graph_ids: [],
      related_graph_ids: [],
      strategies: [],
      revision_kinds: [],
      limit: 8,
      offset: 0,
    });
    expect(screen.getByText("Gateway", { selector: "td" })).toBeInTheDocument();
  });

  it("Refresh repeats the current query", async () => {
    const fetchDocumentCatalog = vi.fn().mockResolvedValue(reply([items[1]]));
    const api = { fetchDocumentCatalog } as unknown as DashboardApi;

    renderCatalog(api);
    await fireEvent.input(screen.getByRole("searchbox"), {
      target: { value: "branch" },
    });
    await waitFor(() => expect(fetchDocumentCatalog).toHaveBeenCalledTimes(2));
    await fireEvent.click(screen.getByRole("button", { name: "Refresh" }));

    await waitFor(() => expect(fetchDocumentCatalog).toHaveBeenCalledTimes(3));
    expect(fetchDocumentCatalog.mock.calls[2][0]).toEqual(
      fetchDocumentCatalog.mock.calls[1][0],
    );
    expect(fetchDocumentCatalog.mock.calls[2][0]).toEqual({
      search: "branch",
      types: [],
      graph_ids: [],
      related_graph_ids: [],
      strategies: [],
      revision_kinds: [],
      limit: 8,
      offset: 0,
    });
  });

  it("ignores an older response that resolves after the latest request", async () => {
    const older = deferred<FetchDocumentCatalogReply>();
    const newer = deferred<FetchDocumentCatalogReply>();
    const fetchDocumentCatalog = vi
      .fn()
      .mockResolvedValueOnce(reply([items[0]]))
      .mockReturnValueOnce(older.promise)
      .mockReturnValueOnce(newer.promise);
    const api = { fetchDocumentCatalog } as unknown as DashboardApi;
    const document = new DocumentCatalogDocument();

    render(DocumentCatalog, { props: { document, api } });
    const refresh = await screen.findByRole("button", { name: "Refresh" });
    refresh.click();
    refresh.click();
    expect(fetchDocumentCatalog).toHaveBeenCalledTimes(3);

    const newerItem = { ...items[0], id: "newer", graph_title: "Newer" };
    newer.resolve(reply([newerItem], 1, [newerItem]));
    await waitFor(() =>
      expect(screen.getByText("Newer", { selector: "td" })).toBeInTheDocument(),
    );

    const olderItem = { ...items[0], id: "older", graph_title: "Older" };
    older.resolve(reply([olderItem], 1, [olderItem]));
    await Promise.resolve();
    await waitFor(() => {
      expect(screen.queryByText("Older", { selector: "td" })).toBeNull();
      expect(document.relatedItems).toEqual([newerItem]);
    });
  });

  it("snapshots related graph ids and keeps the relation scope across table searches", async () => {
    const relatedRevision: DocumentCatalogItem = {
      ...items[0],
      id: "revision-2",
      graph_revision_id: "revision-2",
      parent_revision_id: "revision-1",
      revision_kind: "edit",
      revision_number: 2,
    };
    const fetchDocumentCatalog = vi
      .fn()
      .mockResolvedValueOnce(reply([items[0]]))
      .mockImplementation((query: DocumentCatalogQuery) =>
        Promise.resolve(
          reply(
            [items[0]],
            1,
            query.related_graph_ids.length > 0
              ? [items[0], relatedRevision]
              : [],
          ),
        ),
      );
    const api = { fetchDocumentCatalog } as unknown as DashboardApi;
    const document = new DocumentCatalogDocument();

    const rendered = render(DocumentCatalog, { props: { document, api } });
    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "Select graph-1" }),
      ).toBeInTheDocument(),
    );

    const toggle = screen.getByRole("button", { name: "Show related" });
    expect(toggle).toBeDisabled();
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select graph-1" }),
    );
    expect(toggle).toBeEnabled();
    await fireEvent.click(toggle);

    await waitFor(() => expect(fetchDocumentCatalog).toHaveBeenCalledTimes(2));
    expect(fetchDocumentCatalog.mock.calls[1][0].related_graph_ids).toEqual([
      "graph-1",
    ]);
    await waitFor(() =>
      expect(document.relatedItems).toEqual([items[0], relatedRevision]),
    );

    await fireEvent.input(screen.getByRole("searchbox"), {
      target: { value: "gateway" },
    });
    await waitFor(() => expect(fetchDocumentCatalog).toHaveBeenCalledTimes(3));
    expect(fetchDocumentCatalog.mock.calls[2][0].related_graph_ids).toEqual([
      "graph-1",
    ]);
    expect(document.chosenKeys).toEqual(["graph-1"]);

    await fireEvent.click(toggle);
    await waitFor(() => expect(fetchDocumentCatalog).toHaveBeenCalledTimes(4));
    expect(fetchDocumentCatalog.mock.calls[3][0].related_graph_ids).toEqual([]);
    expect(document.chosenKeys).toEqual(["graph-1"]);
    await waitFor(() => expect(document.relatedItems).toEqual([]));
    rendered.unmount();
  });

  it("bulk-selects the page normally and the complete hierarchy in related mode", async () => {
    const relatedRevision: DocumentCatalogItem = {
      ...items[0],
      id: "revision-2",
      graph_revision_id: "revision-2",
      parent_revision_id: "revision-1",
      revision_kind: "edit",
      revision_number: 2,
    };
    const fetchDocumentCatalog = vi
      .fn()
      .mockImplementation((query: DocumentCatalogQuery) =>
        Promise.resolve(
          query.related_graph_ids.length > 0
            ? reply([items[0]], 2, [items[0], relatedRevision])
            : reply([items[0]], 9),
        ),
      );
    const api = { fetchDocumentCatalog } as unknown as DashboardApi;
    const document = new DocumentCatalogDocument();

    render(DocumentCatalog, { props: { document, api } });
    const selectVisible = await screen.findByRole("checkbox", {
      name: "Select visible documents",
    });
    await fireEvent.click(selectVisible);

    expect(document.chosenKeys).toEqual(["graph-1"]);
    expect(screen.getByText("1 selected · 1 of 9")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Open selected (1)" }),
    ).toBeInTheDocument();

    const toggle = screen.getByRole("button", { name: "Show related" });
    await fireEvent.click(toggle);
    await waitFor(() =>
      expect(document.relatedItems).toEqual([items[0], relatedRevision]),
    );
    const selectRelated = screen.getByRole("checkbox", {
      name: "Select related documents",
    });
    expect(
      screen.queryByRole("checkbox", { name: "Select visible documents" }),
    ).not.toBeInTheDocument();
    expect(selectRelated).toHaveAttribute("aria-checked", "mixed");

    await fireEvent.click(selectRelated);
    expect(document.chosenKeys).toEqual(["graph-1", "revision-2"]);
    expect(
      screen.getByRole("button", { name: "Open selected (2)" }),
    ).toBeInTheDocument();

    await fireEvent.click(toggle);
    await waitFor(() => expect(fetchDocumentCatalog).toHaveBeenCalledTimes(3));
    expect(
      screen.queryByRole("checkbox", { name: "Select related documents" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("checkbox", { name: "Clear all selections" }),
    ).toBeChecked();
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Clear all selections" }),
    );
    expect(document.chosenKeys).toEqual([]);
    expect(screen.getByText("0 selected · 1 of 9")).toBeInTheDocument();
  });
});
