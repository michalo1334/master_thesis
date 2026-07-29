import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import type { LoadedGraph } from "../contract";
import { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
import { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";
import DocumentOutline from "./DocumentOutline.svelte";

function graph(
  id: string,
  title: string,
  parentId: string | null = null,
): EditableGraphDocument {
  const document = new EditableGraphDocument();
  const loadedGraph: LoadedGraph = {
    id,
    title,
    lock_version: 1,
    parent_id: parentId,
    tags: [],
    nodes: [],
    edges: [],
  };
  document.replaceFromLoadedGraph(loadedGraph);
  return document;
}

function depth(name: string): string | null {
  return (
    screen.getByRole("button", { name, hidden: true }).closest("li")?.dataset
      .depth ?? null
  );
}

afterEach(cleanup);

describe("DocumentOutline", () => {
  it("nests open child graphs and their reports", async () => {
    const root = graph("root", "Root");
    const child = graph("child", "Child", root.loadedGraphId);
    const report = new SimulationReportDocument("Child", child.loadedGraphId!);
    const onSelectDocument = vi.fn();

    render(DocumentOutline, {
      props: {
        documents: [root, child, report],
        selectedDocumentId: child.id,
        collapsed: false,
        onCollapsedChange: vi.fn(),
        onSelectDocument,
      },
    });

    expect(depth("Graph Root")).toBe("0");
    expect(depth("Graph Child")).toBe("1");
    expect(depth(`Report ${report.title}`)).toBe("2");
    expect(
      screen.getByRole("button", { name: "Graph Child", hidden: true }),
    ).toHaveAttribute("aria-current", "page");
    expect(
      screen
        .getByRole("button", { name: "Graph Root", hidden: true })
        .querySelector(".hero-share"),
    ).toBeInTheDocument();
    expect(
      screen
        .getByRole("button", { name: `Report ${report.title}`, hidden: true })
        .querySelector(".hero-shield-check"),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", {
        name: "Collapse document outline",
        hidden: true,
      }),
    ).toHaveAttribute("aria-expanded", "true");

    await fireEvent.click(
      screen.getByRole("button", { name: "Graph Child", hidden: true }),
    );
    expect(onSelectDocument).toHaveBeenCalledWith(child.id);
  });

  it("shows a child graph at the root when its parent is closed", () => {
    const child = graph("child", "Child", "closed-parent");

    render(DocumentOutline, {
      props: {
        documents: [child],
        collapsed: false,
        onCollapsedChange: vi.fn(),
        onSelectDocument: vi.fn(),
      },
    });

    expect(depth("Graph Child")).toBe("0");
  });

  it("places reports without an open graph in the Reports group", () => {
    const report = new SimulationReportDocument("Closed graph", "closed-graph");

    render(DocumentOutline, {
      props: {
        documents: [report],
        collapsed: false,
        onCollapsedChange: vi.fn(),
        onSelectDocument: vi.fn(),
      },
    });

    expect(
      screen.getByRole("heading", { name: "Reports", hidden: true }),
    ).toBeInTheDocument();
    expect(depth(`Report ${report.title}`)).toBe("1");
  });

  it("selects a report when clicked", async () => {
    const report = new SimulationReportDocument("Graph", "graph");
    const onSelectDocument = vi.fn();

    render(DocumentOutline, {
      props: {
        documents: [report],
        collapsed: false,
        onCollapsedChange: vi.fn(),
        onSelectDocument,
      },
    });

    await fireEvent.click(
      screen.getByRole("button", {
        name: `Report ${report.title}`,
        hidden: true,
      }),
    );
    expect(onSelectDocument).toHaveBeenCalledWith(report.id);
  });

  it("requests a controlled outline expansion", async () => {
    const onCollapsedChange = vi.fn();

    render(DocumentOutline, {
      props: {
        documents: [graph("graph", "Graph")],
        collapsed: true,
        onCollapsedChange,
        onSelectDocument: vi.fn(),
      },
    });

    const toggle = screen.getByRole("button", {
      name: "Expand document outline",
      hidden: true,
    });
    expect(toggle).toHaveAttribute("aria-expanded", "false");
    expect(
      screen.queryByRole("button", { name: "Graph Graph", hidden: true }),
    ).not.toBeInTheDocument();

    await fireEvent.click(toggle);
    expect(onCollapsedChange).toHaveBeenCalledWith(false);
  });
});
