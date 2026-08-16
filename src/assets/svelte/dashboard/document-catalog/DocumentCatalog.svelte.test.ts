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
import type { DocumentCatalogItem } from "../contract";

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
    id: "simulation-1",
    kind: "simulation_report",
    graph_id: "graph-1",
    graph_revision_id: "revision-1",
    graph_title: "Gateway",
    analysis_id: "analysis-1",
    revision_kind: "original",
    revision_number: 1,
    created_at: "2026-01-02T00:00:00Z",
  },
  {
    id: "optimization-1",
    kind: "optimization_report",
    graph_id: "graph-2",
    graph_revision_id: "revision-2",
    graph_title: "Branch",
    analysis_id: "analysis-1",
    revision_kind: "derived",
    revision_number: 2,
    strategy: "greedy",
    created_at: "2026-01-03T00:00:00Z",
  },
  {
    id: "simulation-2",
    kind: "simulation_report",
    graph_id: "graph-2",
    graph_revision_id: "revision-2",
    graph_title: "Branch",
    analysis_id: "analysis-2",
    revision_kind: "derived",
    revision_number: 2,
    created_at: "2026-01-04T00:00:00Z",
  },
];

afterEach(cleanup);

describe("DocumentCatalog", () => {
  it("filters catalog rows with OR within a field and AND across fields", async () => {
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue({ items }),
    } as unknown as DashboardApi;

    render(DocumentCatalog, {
      props: { document: new DocumentCatalogDocument(), api, onOpen: vi.fn() },
    });

    await waitFor(() =>
      expect(
        screen.getAllByText("Simulation report", { selector: "td" }),
      ).toHaveLength(2),
    );
    for (const label of [
      "Type",
      "Graph",
      "Revision kind",
      "Analysis ID",
      "Strategy",
    ]) {
      const filter = screen.getByRole("button", {
        name: `${label} filter, 0 selected`,
      });
      expect(filter).toHaveTextContent("");
      expect(filter.querySelector(".hero-funnel")).toBeInTheDocument();
    }

    await fireEvent.click(
      screen.getByRole("button", { name: "Type filter, 0 selected" }),
    );
    await fireEvent.click(screen.getByRole("checkbox", { name: "Graph" }));
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Simulation report" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Graph filter, 0 selected" }),
    );
    await fireEvent.click(screen.getByRole("checkbox", { name: "Gateway" }));

    expect(
      screen
        .getByRole("button", { name: "Type filter, 2 selected" })
        .querySelector(".multi-select-filter-count"),
    ).toHaveTextContent("2");
    expect(
      screen
        .getByRole("button", { name: "Graph filter, 1 selected" })
        .querySelector(".multi-select-filter-count"),
    ).toHaveTextContent("1");

    expect(
      screen.getAllByText("Simulation report", { selector: "td" }),
    ).toHaveLength(1);
    expect(screen.getByText("Graph", { selector: "td" })).toBeInTheDocument();
    expect(
      screen.queryByText("Optimization report", { selector: "td" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByText("Branch", { selector: "td" }),
    ).not.toBeInTheDocument();
  });

  it("keeps header filters accessible when they exclude all catalog rows", async () => {
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue({ items }),
    } as unknown as DashboardApi;

    render(DocumentCatalog, {
      props: { document: new DocumentCatalogDocument(), api, onOpen: vi.fn() },
    });

    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Type filter, 0 selected" }),
      ).toBeInTheDocument(),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Type filter, 0 selected" }),
    );
    await fireEvent.click(screen.getByRole("checkbox", { name: "Graph" }));
    await fireEvent.click(
      screen.getByRole("button", { name: "Graph filter, 0 selected" }),
    );
    await fireEvent.click(screen.getByRole("checkbox", { name: "Branch" }));

    expect(screen.getByRole("status")).toHaveTextContent(
      "No documents match the selected filters.",
    );
    for (const label of [
      "Type filter, 1 selected",
      "Graph filter, 1 selected",
      "Revision kind filter, 0 selected",
      "Analysis ID filter, 0 selected",
      "Strategy filter, 0 selected",
    ]) {
      expect(screen.getByRole("button", { name: label })).toBeInTheDocument();
    }
  });

  it("does not restore selections cleared by catalog filters", async () => {
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue({ items }),
    } as unknown as DashboardApi;

    render(DocumentCatalog, {
      props: { document: new DocumentCatalogDocument(), api, onOpen: vi.fn() },
    });

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
      screen.getByRole("checkbox", { name: "Simulation report" }),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Simulation report" }),
    );

    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "Select graph-1" }),
      ).not.toBeChecked(),
    );
    expect(
      screen.getByRole("button", { name: "Open selected (0)" }),
    ).toBeDisabled();
  });

  it("opens selected documents sequentially and locks controls while opening", async () => {
    let resolveFirst!: () => void;
    const firstOpen = new Promise<void>((resolve) => {
      resolveFirst = resolve;
    });
    const onOpen = vi
      .fn()
      .mockReturnValueOnce(firstOpen)
      .mockResolvedValueOnce(true);
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue({ items }),
    } as unknown as DashboardApi;

    render(DocumentCatalog, {
      props: { document: new DocumentCatalogDocument(), api, onOpen },
    });

    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "Select graph-1" }),
      ).toBeInTheDocument(),
    );

    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select graph-1" }),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select simulation-1" }),
    );

    const openButton = screen.getByRole("button", {
      name: "Open selected (2)",
    });
    await fireEvent.click(openButton);

    expect(onOpen).toHaveBeenCalledTimes(1);
    expect(onOpen).toHaveBeenLastCalledWith(items[0]);
    expect(openButton).toBeDisabled();
    expect(
      screen.getByRole("checkbox", { name: "Select graph-1" }),
    ).toBeDisabled();

    resolveFirst();
    await waitFor(() => expect(onOpen).toHaveBeenCalledTimes(2));
    expect(onOpen).toHaveBeenLastCalledWith(items[1]);
    await waitFor(() => expect(openButton).toBeEnabled());
  });

  it("refreshes the catalog and disables Refresh while loading", async () => {
    let resolveRefresh!: (value: { items: DocumentCatalogItem[] }) => void;
    const refresh = new Promise<{ items: DocumentCatalogItem[] }>((resolve) => {
      resolveRefresh = resolve;
    });
    const api = {
      fetchDocumentCatalog: vi
        .fn()
        .mockResolvedValueOnce({ items })
        .mockReturnValueOnce(refresh),
    } as unknown as DashboardApi;

    render(DocumentCatalog, {
      props: { document: new DocumentCatalogDocument(), api, onOpen: vi.fn() },
    });

    await waitFor(() =>
      expect(screen.getByRole("button", { name: "Refresh" })).toBeEnabled(),
    );

    const refreshButton = screen.getByRole("button", { name: "Refresh" });
    await fireEvent.click(refreshButton);

    expect(api.fetchDocumentCatalog).toHaveBeenCalledTimes(2);
    expect(refreshButton).toBeDisabled();

    resolveRefresh({ items });
    await waitFor(() => expect(refreshButton).toBeEnabled());
  });

  it("removes stale filters and selections after refresh", async () => {
    const refreshedItems = [items[0]];
    const api = {
      fetchDocumentCatalog: vi
        .fn()
        .mockResolvedValueOnce({ items })
        .mockResolvedValueOnce({ items: refreshedItems }),
    } as unknown as DashboardApi;

    render(DocumentCatalog, {
      props: { document: new DocumentCatalogDocument(), api, onOpen: vi.fn() },
    });

    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Graph filter, 0 selected" }),
      ).toBeInTheDocument(),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Graph filter, 0 selected" }),
    );
    await fireEvent.click(screen.getByRole("checkbox", { name: "Branch" }));
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select simulation-2" }),
    );
    await fireEvent.click(screen.getByRole("button", { name: "Refresh" }));

    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Graph filter, 0 selected" }),
      ).toBeInTheDocument(),
    );
    expect(screen.getByText("Gateway", { selector: "td" })).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Open selected (0)" }),
    ).toBeDisabled();
  });
});
