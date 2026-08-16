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
import type { DashboardApi } from "../dashboard-api";
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
    analysis_ids: [],
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
    analysis_ids: ["analysis-1", "analysis-2"],
    revision_kind: "optimization",
    revision_number: 4,
    output_revision_kind: "optimization",
    output_revision_number: 23,
    strategy: "greedy",
    created_at: "2026-01-03T00:00:00Z",
  },
];

function reply(
  catalogItems: DocumentCatalogItem[] = items,
  total_count = catalogItems.length,
): FetchDocumentCatalogReply {
  return {
    items: catalogItems,
    total_count,
    filter_options: {
      types: ["graph", "optimization_report"],
      graphs: [
        { id: "graph-1", title: "Gateway" },
        { id: "graph-2", title: "Branch" },
      ],
      analysis_ids: ["analysis-1", "analysis-2"],
      strategies: ["greedy"],
      revision_kinds: ["original", "optimization"],
    },
  };
}

function renderCatalog(api: DashboardApi, onOpen = vi.fn()) {
  return render(DocumentCatalog, {
    props: { document: new DocumentCatalogDocument(), api, onOpen },
  });
}

afterEach(cleanup);

describe("DocumentCatalog", () => {
  it("uses catalog replies for rows, options, analysis, and output revisions", async () => {
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue(reply()),
    } as unknown as DashboardApi;

    renderCatalog(api);

    await waitFor(() => expect(screen.getByText("many")).toBeInTheDocument());
    expect(
      screen.getByText("optimization #4 -> optimization #23"),
    ).toBeInTheDocument();
    expect(screen.getByText("2 of 2")).toBeInTheDocument();

    await fireEvent.click(
      screen.getByRole("button", { name: "Analysis ID filter, 0 selected" }),
    );
    expect(
      screen.getByRole("checkbox", { name: "analysis-1" }),
    ).toBeInTheDocument();
  });

  it("sends filters to the backend and clears the selection", async () => {
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue(reply()),
    } as unknown as DashboardApi;

    renderCatalog(api);
    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "Select graph-1" }),
      ).toBeInTheDocument(),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select graph-1" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Type filter, 0 selected" }),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Optimization report" }),
    );

    await waitFor(() =>
      expect(api.fetchDocumentCatalog).toHaveBeenCalledTimes(2),
    );
    expect(api.fetchDocumentCatalog).toHaveBeenLastCalledWith({
      search: "",
      types: ["optimization_report"],
      graph_ids: [],
      analysis_ids: [],
      strategies: [],
      revision_kinds: [],
      limit: 8,
      offset: 0,
    });
    expect(
      screen.getByRole("button", { name: "Open selected (0)" }),
    ).toBeDisabled();
  });

  it("keeps selected documents from visited pages", async () => {
    const secondPage = [
      {
        ...items[1],
        id: "optimization-2",
        analysis_ids: ["analysis-1"],
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
      analysis_ids: [],
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
      analysis_ids: [],
      strategies: [],
      revision_kinds: [],
      limit: 8,
      offset: 0,
    });
  });
});
