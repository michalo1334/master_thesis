import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import UnplacedTray from "./UnplacedTray.svelte";
import {
  buildTopologyFixture,
  MISSING_REFERENCE_ID,
  NO_PLACEMENT_ENTITY_ID,
  PENDING_ENTITY_ID,
  PLACEMENT_ISSUE_ENTITY_ID,
} from "./topology-test-fixture";

afterEach(cleanup);

function renderTray({ onClose }: { onClose?: () => void } = {}) {
  const { scene } = buildTopologyFixture();
  const onSelect = vi.fn();
  const result = render(UnplacedTray, { props: { scene, onSelect, onClose } });
  return { onSelect, ...result };
}

function row(container: HTMLElement, entityId: string): Element | null {
  return container.querySelector(`[data-unplaced-entity='${entityId}']`);
}

describe("UnplacedTray", () => {
  it("counts the entities the projection cannot place", () => {
    const { container } = renderTray();

    expect(
      container
        .querySelector(".topology-unplaced-tray")
        ?.getAttribute("data-unplaced-count"),
    ).toBe("4");
    expect(screen.getByText(/Unplaced · 4/)).toBeInTheDocument();
  });

  it("states the typed reason for each entity", () => {
    const { container } = renderTray();

    expect(
      row(container, PLACEMENT_ISSUE_ENTITY_ID)?.getAttribute(
        "data-unplaced-reason",
      ),
    ).toBe("host_without_segment");
    expect(
      screen.getByRole("button", { name: "host-7, no segment" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "orphan-svc, no host" }),
    ).toBeInTheDocument();
    expect(row(container, MISSING_REFERENCE_ID)?.textContent).toContain(
      "missing host",
    );
    expect(
      screen.getByRole("button", { name: "dns-1, awaiting topology update" }),
    ).toBeInTheDocument();
  });

  it("cues a pending change apart from a placement issue", () => {
    const { container } = renderTray();

    const pending = row(container, PENDING_ENTITY_ID);
    const issue = row(container, PLACEMENT_ISSUE_ENTITY_ID);
    const noPlacement = row(container, NO_PLACEMENT_ENTITY_ID);

    expect(pending?.classList.contains("is-pending")).toBe(true);
    expect(issue?.classList.contains("is-pending")).toBe(false);
    expect(noPlacement?.getAttribute("data-unplaced-status")).toBe(
      "no_placement",
    );
  });

  it("selects an entity when the user picks it", async () => {
    const { onSelect } = renderTray();

    await fireEvent.click(
      screen.getByRole("button", { name: "host-7, no segment" }),
    );

    expect(onSelect).toHaveBeenCalledWith({
      kind: "node",
      id: PLACEMENT_ISSUE_ENTITY_ID,
    });
  });

  it("closes from the tray header", async () => {
    const onClose = vi.fn();
    renderTray({ onClose });

    await fireEvent.click(
      screen.getByRole("button", { name: "Close unplaced tray" }),
    );

    expect(onClose).toHaveBeenCalledOnce();
  });

  it("names the entities an issue relates to", () => {
    const { container } = renderTray();

    expect(row(container, PLACEMENT_ISSUE_ENTITY_ID)?.textContent).toContain(
      "Related: Zone A",
    );
  });

  it("reports a broken reference without a graph entity", () => {
    const { container } = renderTray();

    expect(
      row(container, MISSING_REFERENCE_ID)?.getAttribute(
        "data-unplaced-status",
      ),
    ).toBe("missing_reference");
  });

  it("names the projection records that carry a broken reference", () => {
    const { container } = renderTray();

    // The segment record is the owner that names the absent host.
    expect(row(container, MISSING_REFERENCE_ID)?.textContent).toContain(
      "Related: Zone A",
    );
  });

  it("offers no selection for an entity the graph does not contain", async () => {
    const { container, onSelect } = renderTray();
    const missing = row(container, MISSING_REFERENCE_ID)!;

    expect(missing.getAttribute("data-unplaced-selectable")).toBe("false");
    expect(missing.tagName).toBe("DIV");
    expect(missing.textContent).toContain("missing host");

    await fireEvent.click(missing);

    expect(onSelect).not.toHaveBeenCalled();
  });
});
