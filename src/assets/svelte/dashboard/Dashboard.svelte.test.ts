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
import { MAX_STUDY_RESULTS_ARCHIVE_BYTES } from "./analysis-report/study-results-import";

afterEach(cleanup);

function studyAnalysis(mode: "pilot" | "analyze") {
  return {
    capability_results: [],
    feasibility_summary: [],
    metadata: {
      command_mode: mode,
      family_scope: "study",
      family_size: 1,
      runtime_summary: {
        median_plan_selection_runtime_ms: 0,
        median_simulation_runtime_ms: 0,
        evaluator_runtime_ms: 0,
      },
      schema_version: 1,
      ...(mode === "pilot"
        ? {
            recommended_plan_selection_seed_count: 3,
            recommended_attacks_per_plan: 8,
            insufficient_pilot: false,
          }
        : {}),
    },
    pilot_results: [],
    primary_results: [],
    secondary_results: [],
  };
}

function importFile(size = 5): File {
  const file = new File(["study"], "study-results.zip", {
    type: "application/zip",
  });
  Object.defineProperty(file, "size", { value: size });
  Object.defineProperty(file, "arrayBuffer", {
    value: async () => new TextEncoder().encode("study").buffer,
  });
  return file;
}

async function dispatchStudyFile(
  input: HTMLInputElement,
  file?: File,
): Promise<void> {
  await fireEvent.change(input, { target: { files: file ? [file] : [] } });
}

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
        related_items: [],
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

  it("does not import when the picker has no file", async () => {
    const api = { importStudyResults: vi.fn() } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    render(Dashboard, { props: { model } });

    await fireEvent.click(
      screen.getByRole("button", { name: "Open study results" }),
    );
    await dispatchStudyFile(
      screen.getByLabelText("Select study results ZIP") as HTMLInputElement,
    );

    expect(api.importStudyResults).not.toHaveBeenCalled();
    expect(model.workspace.documents).toHaveLength(0);
  });

  it("rejects an oversized study ZIP before sending it", async () => {
    const api = { importStudyResults: vi.fn() } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    render(Dashboard, { props: { model } });

    await dispatchStudyFile(
      screen.getByLabelText("Select study results ZIP") as HTMLInputElement,
      importFile(MAX_STUDY_RESULTS_ARCHIVE_BYTES + 1),
    );

    expect(api.importStudyResults).not.toHaveBeenCalled();
    expect(model.workspace.statusMessage).toContain("must not exceed");
  });

  it("disables the control, announces loading, and moves focus to the visible status", async () => {
    let resolveImport: (value: {
      status: "ok";
      analysis: ReturnType<typeof studyAnalysis>;
    }) => void;
    const api = {
      importStudyResults: vi.fn().mockImplementation(
        () =>
          new Promise<{
            status: "ok";
            analysis: ReturnType<typeof studyAnalysis>;
          }>((resolve) => {
            resolveImport = resolve;
          }),
      ),
    } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    render(Dashboard, { props: { model } });

    await dispatchStudyFile(
      screen.getByLabelText("Select study results ZIP") as HTMLInputElement,
      importFile(),
    );

    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Open study results" }),
      ).toBeDisabled(),
    );
    const status = screen.getByRole("status");
    expect(status).toHaveTextContent("Opening study results…");
    expect(status).toHaveAttribute("aria-live", "polite");
    expect(globalThis.document.activeElement).toBe(status);

    resolveImport!({ status: "ok", analysis: studyAnalysis("analyze") });
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Open study results" }),
      ).toBeEnabled(),
    );
  });

  it("ignores a second selection while the first import is still reading", async () => {
    let resolveFirstRead: (value: ArrayBuffer) => void;
    const firstFile = {
      size: 5,
      arrayBuffer: () =>
        new Promise<ArrayBuffer>((resolve) => {
          resolveFirstRead = resolve;
        }),
    } as unknown as File;
    const secondFile = {
      size: 5,
      arrayBuffer: vi.fn(),
    } as unknown as File;
    const api = {
      importStudyResults: vi.fn().mockResolvedValue({
        status: "ok",
        analysis: studyAnalysis("analyze"),
      }),
    } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    render(Dashboard, { props: { model } });
    const input = screen.getByLabelText(
      "Select study results ZIP",
    ) as HTMLInputElement;

    await dispatchStudyFile(input, firstFile);
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Open study results" }),
      ).toBeDisabled(),
    );
    await dispatchStudyFile(input, secondFile);

    expect(secondFile.arrayBuffer).not.toHaveBeenCalled();
    resolveFirstRead!(new TextEncoder().encode("study").buffer);
    await waitFor(() => expect(api.importStudyResults).toHaveBeenCalledOnce());
  });

  it("opens a study document only after a successful import", async () => {
    const api = {
      importStudyResults: vi.fn().mockResolvedValue({
        status: "ok",
        analysis: studyAnalysis("analyze"),
      }),
    } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    render(Dashboard, { props: { model } });

    await dispatchStudyFile(
      screen.getByLabelText("Select study results ZIP") as HTMLInputElement,
      importFile(),
    );

    await waitFor(() =>
      expect(model.workspace.activeDocument?.kind).toBe(
        "imported-study-results",
      ),
    );
    expect(api.importStudyResults).toHaveBeenCalledWith({
      archive: "c3R1ZHk=",
    });
    expect(
      screen.getByRole("heading", { name: "Imported study results" }),
    ).toBeInTheDocument();
    expect(globalThis.document.activeElement).toHaveAttribute(
      "data-imported-study-results",
    );
  });

  it("keeps the active workspace unchanged after an invalid study result", async () => {
    const api = {
      importStudyResults: vi.fn().mockResolvedValue({
        status: "error",
        analysis: null,
        error: { code: "invalid_archive", message: "Invalid archive." },
      }),
    } as unknown as DashboardApi;
    const model = new DashboardModel(api);
    const catalog = model.workspace.openDocumentCatalog();
    render(Dashboard, { props: { model } });

    await dispatchStudyFile(
      screen.getByLabelText("Select study results ZIP") as HTMLInputElement,
      importFile(),
    );

    await waitFor(() => expect(api.importStudyResults).toHaveBeenCalledOnce());
    expect(model.workspace.activeDocument?.id).toBe(catalog.id);
    expect(model.workspace.statusMessage).toContain(
      "Select a valid mix evaluate.study result ZIP.",
    );
    expect(
      model.workspace.documents.some(
        (document) => document.kind === "imported-study-results",
      ),
    ).toBe(false);
  });
});
