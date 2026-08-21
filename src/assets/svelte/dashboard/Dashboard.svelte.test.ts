import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import Dashboard from "../Dashboard.svelte";
import { DashboardModel } from "./DashboardModel.svelte";
import type { DashboardApi } from "./dashboard-api";
import { createWorkspaceEnvelope } from "../ui-kit/workspace/workspace-persistence";

afterEach(cleanup);

describe("Dashboard document content", () => {
  it("loads a restored graph when its tab is selected", async () => {
    const api = {
      fetchGraphConnectivity: vi.fn().mockResolvedValue({ rules: [] }),
      openGraph: vi.fn().mockResolvedValue({
        status: "ok",
        graph: {
          id: "graph-1",
          title: "Topology",
          revision_id: "revision-1",
          parent_revision_id: null,
          revision_kind: "original",
          revision_number: 1,
          nodes: [],
          edges: [],
        },
      }),
    } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    const persistence = model.workspace.toPersistence();
    model.workspace.restorePersistence(
      createWorkspaceEnvelope(
        {
          state: persistence!.state,
          documents: [
            { kind: "document-catalog", ids: {}, title: "Documents" },
            {
              kind: "graph",
              ids: { revisionId: "revision-1" },
              title: "Topology",
            },
          ],
          selectedDocumentKey: "document-catalog",
        },
        1,
      ),
    );

    render(Dashboard, { props: { model } });

    await fireEvent.click(screen.getByRole("tab", { name: "Topology" }));

    await waitFor(() =>
      expect(api.openGraph).toHaveBeenCalledWith("revision-1"),
    );
  });

  it("opens catalog selections through the workspace callback", async () => {
    const api = {
      fetchDocumentCatalog: vi.fn().mockResolvedValue({
        items: [
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
        ],
        total_count: 1,
        filter_options: {
          types: ["graph"],
          graphs: [{ id: "graph-1", title: "Gateway" }],
          strategies: [],
          revision_kinds: ["original"],
        },
      }),
      openGraph: vi.fn().mockResolvedValue({ status: "not_found" }),
    } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    model.workspace.openDocumentCatalog();

    render(Dashboard, { props: { model } });

    await waitFor(() =>
      expect(
        screen.getByRole("checkbox", { name: "Select graph-1" }),
      ).toBeInTheDocument(),
    );
    await fireEvent.click(
      screen.getByRole("checkbox", { name: "Select graph-1" }),
    );
    await fireEvent.click(
      screen.getByRole("button", { name: "Open selected (1)" }),
    );

    await waitFor(() =>
      expect(api.openGraph).toHaveBeenCalledWith("revision-1"),
    );
  });
});
