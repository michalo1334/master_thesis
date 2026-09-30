import type { ManifestSummary } from "../../contracts.generated/dashboard/evaluation";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import type { DashboardApi } from "../dashboard-api";
import { ManifestModel } from "./ManifestModel.svelte";
import ManifestDialog from "./ManifestDialog.svelte";

function summary(): ManifestSummary {
  return {
    id: "manifest-1",
    manifest_id: "fixed-enterprise-v1",
    title: "Baseline manifest",
    content: {
      schema_version: 3,
      id: "fixed-enterprise-v1",
      evaluation: { trials: 100, seed: 9001 },
    },
  };
}

function manifestApi() {
  const manifest = summary();
  return {
    listManifests: vi.fn().mockResolvedValue({ manifests: [manifest] }),
    getManifest: vi.fn().mockResolvedValue({ manifest }),
    saveManifest: vi.fn(),
    startEvaluation: vi.fn(),
    describeManifest: vi.fn().mockResolvedValue({
      status: "ok",
      description: null,
      errors: [],
    }),
  };
}

async function renderDialog() {
  const api = manifestApi();
  const model = new ManifestModel(api as unknown as DashboardApi);
  render(ManifestDialog, { props: { model } });
  await model.openDialog();
  return { api, model };
}

afterEach(cleanup);

describe("ManifestDialog", () => {
  it("lists saved manifests with JSON and Preview tabs", async () => {
    const { model } = await renderDialog();

    expect(screen.getByText("Evaluation manifests")).toBeInTheDocument();
    expect(screen.getByText("Baseline manifest")).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "JSON" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Preview" })).toBeInTheDocument();
    expect(model.open).toBe(true);
  });

  it("keeps Start evaluation gated on a saved, unmodified manifest", async () => {
    const { model } = await renderDialog();

    expect(
      screen.getByRole("button", { name: "Start evaluation" }),
    ).toBeDisabled();

    await model.selectManifest("manifest-1");
    await waitFor(() =>
      expect(
        screen.getByRole("button", { name: "Start evaluation" }),
      ).toBeEnabled(),
    );

    await fireEvent.input(screen.getByLabelText("Manifest JSON"), {
      target: { value: `${model.editorText} ` },
    });

    expect(
      screen.getByRole("button", { name: "Start evaluation" }),
    ).toBeDisabled();
  });

  it("describes the manifest from the Preview tab", async () => {
    const { api, model } = await renderDialog();
    await model.selectManifest("manifest-1");

    await fireEvent.click(screen.getByRole("tab", { name: "Preview" }));

    await waitFor(() => expect(api.describeManifest).toHaveBeenCalledOnce());
    expect(api.describeManifest).toHaveBeenCalledWith(
      expect.objectContaining({ id: "fixed-enterprise-v1" }),
    );
  });
});
