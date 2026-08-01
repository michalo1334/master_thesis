import {
  afterAll,
  afterEach,
  beforeAll,
  describe,
  expect,
  it,
  vi,
} from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import OptimizationReportComponent from "./OptimizationReport.svelte";
import { OptimizationReportDocument } from "./OptimizationReportDocument.svelte";
import { GraphDiffDocument } from "../graph/GraphDiffDocument.svelte";
import type { GraphDiffResult, OptimizationReport } from "../contract";

afterEach(cleanup);

beforeAll(() => {
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      unobserve() {}
      disconnect() {}
    },
  );
});

afterAll(() => vi.unstubAllGlobals());

describe("OptimizationReport", () => {
  function createDocument(
    createGraphDiff?: () => Promise<GraphDiffDocument | undefined>,
  ): OptimizationReportDocument {
    const document = new OptimizationReportDocument({
      graphId: "g1",
      graphTitle: "Topology",
      correlationId: "corr-1",
      strategy: "cvss",
      budget: 2,
    });
    document.complete(
      {
        correlation_id: "corr-1",
        graph_id: "g1",
        optimized_graph_id: "optimized-g1",
        report: {
          strategy: "cvss",
          requested_budget: 2,
          used_budget: 1,
          runtime_ms: 25,
          actions: [],
        },
      },
      vi.fn().mockResolvedValue(true),
      createGraphDiff,
    );
    return document;
  }

  function createGraphDiffDocument(): GraphDiffDocument {
    const graph = {
      id: "g1",
      title: "Topology",
      lock_version: 1,
      parent_id: null,
      tags: [],
      nodes: [],
      edges: [],
    };
    const result: GraphDiffResult = {
      graph,
      node_status: [],
      edge_status: [],
      node_counts: { added: 0, removed: 0, unchanged: 0 },
      edge_counts: { added: 0, removed: 0, unchanged: 0 },
    };
    return new GraphDiffDocument(
      graph,
      {
        id: "g2",
        title: "Optimized topology",
      },
      result,
    );
  }

  it("separates the overview, defense plan, and unknown strategy fallback", async () => {
    const openOptimizedGraph = vi.fn().mockResolvedValue(true);
    const document = new OptimizationReportDocument({
      graphId: "g1",
      graphTitle: "Topology",
      correlationId: "corr-1",
      strategy: "cvss",
      budget: 2,
    });
    document.complete(
      {
        correlation_id: "corr-1",
        graph_id: "g1",
        optimized_graph_id: "optimized-g1",
        report: {
          strategy: "future_strategy",
          requested_budget: 2,
          used_budget: 1,
          runtime_ms: 25,
          actions: [
            {
              id: "patch-1",
              label: "Patch CVE-1",
              kind: "patch_vulnerability",
              cost: 1,
              cvss_score: 9.8,
            },
          ],
        } as unknown as OptimizationReport,
      },
      openOptimizedGraph,
    );

    render(OptimizationReportComponent, { props: { document } });

    await fireEvent.click(
      screen.getByRole("button", { name: "Open optimized graph" }),
    );
    expect(openOptimizedGraph).toHaveBeenCalledOnce();

    await fireEvent.click(screen.getByRole("tab", { name: "Defense plan" }));
    expect(
      screen.getByRole("columnheader", { name: "Action" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("columnheader", { name: "CVSS" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Patch CVE-1")).toBeInTheDocument();

    await fireEvent.click(
      screen.getByRole("tab", { name: "Strategy analysis" }),
    );
    expect(
      screen.getByRole("heading", { name: "Strategy analysis unavailable" }),
    ).toBeInTheDocument();
  });

  it("loads and displays the graph diff", async () => {
    let resolveGraphDiff!: (graphDiff: GraphDiffDocument | undefined) => void;
    const createGraphDiff = vi.fn(
      () =>
        new Promise<GraphDiffDocument | undefined>((resolve) => {
          resolveGraphDiff = resolve;
        }),
    );
    const document = createDocument(createGraphDiff);
    const loadGraphDiff = vi.spyOn(document, "loadGraphDiff");
    render(OptimizationReportComponent, {
      props: { document },
    });

    await fireEvent.click(screen.getByRole("tab", { name: "Graph diff" }));
    expect(loadGraphDiff).toHaveBeenCalledOnce();
    expect(createGraphDiff).toHaveBeenCalledOnce();
    expect(screen.getByText("Loading graph diff…")).toBeInTheDocument();

    resolveGraphDiff(createGraphDiffDocument());
    await waitFor(() => {
      expect(
        screen.getByRole("region", {
          name: "Read-only graph comparison canvas",
        }),
      ).toBeInTheDocument();
    });
  });

  it("keeps the tab list compact within the constrained report shell", () => {
    const document = createDocument();
    const { container } = render(OptimizationReportComponent, {
      props: { document },
    });
    const report = container.querySelector(".optimization-report");
    const tabs = screen.getByRole("tablist").parentElement;
    const tabList = screen.getByRole("tablist");
    const panel = screen.getByRole("tabpanel");

    expect(report).not.toBeNull();
    expect(tabs).not.toBeNull();
    expect(getComputedStyle(report!).overflow).toBe("hidden");
    expect(getComputedStyle(tabs!).height).toBe("100%");
    expect(getComputedStyle(tabList).alignSelf).toBe("start");
    expect(getComputedStyle(panel).overflow).toBe("auto");
  });
});
