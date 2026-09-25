import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import TopologyNavigator from "./TopologyNavigator.svelte";
import {
  buildTopologyFixture,
  MISSING_REFERENCE_ID,
  NO_PLACEMENT_ENTITY_ID,
  PENDING_ENTITY_ID,
  PLACEMENT_ISSUE_ENTITY_ID,
} from "./topology-test-fixture";

afterEach(cleanup);

function renderNavigator(selectedEntityId?: string) {
  const { scene } = buildTopologyFixture();
  const onSelect = vi.fn();
  const result = render(TopologyNavigator, {
    props: { scene, onSelect, selectedEntityId },
  });
  return { onSelect, ...result };
}

function unplacedRow(container: HTMLElement, entityId: string): Element | null {
  return container.querySelector(
    `[data-navigator-kind='unplaced'][data-navigator-entity='${entityId}']`,
  );
}

describe("TopologyNavigator", () => {
  it("shows segments, hosts, and services as one hierarchy", () => {
    renderNavigator();

    expect(
      screen.getByRole("button", { name: "Segment Zone A" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Host web-1" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Host dns-1" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Service nginx" }),
    ).toBeInTheDocument();
  });

  it("shows attached context in its own section", () => {
    const { container } = renderNavigator();

    expect(
      container.querySelector("[data-navigator-kind='context']"),
    ).not.toBeNull();
    expect(
      screen.getByRole("button", { name: "Credential depl-cred" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Attached context")).toBeInTheDocument();
  });

  it("shows every Unplaced entity with its reason", () => {
    const { container } = renderNavigator();

    expect(screen.getByText("Unplaced")).toBeInTheDocument();
    expect(
      unplacedRow(container, PLACEMENT_ISSUE_ENTITY_ID)?.getAttribute(
        "data-unplaced-status",
      ),
    ).toBe("placement_issue");
    expect(
      unplacedRow(container, NO_PLACEMENT_ENTITY_ID)?.getAttribute(
        "data-unplaced-status",
      ),
    ).toBe("no_placement");
    expect(
      unplacedRow(container, MISSING_REFERENCE_ID)?.getAttribute(
        "data-unplaced-status",
      ),
    ).toBe("missing_reference");
    expect(
      unplacedRow(container, PENDING_ENTITY_ID)?.getAttribute(
        "data-unplaced-status",
      ),
    ).toBe("pending");
  });

  it("activates the entity the user picks", async () => {
    const { onSelect } = renderNavigator();

    await fireEvent.click(
      screen.getByRole("button", { name: "Service nginx" }),
    );

    expect(onSelect).toHaveBeenCalledWith({ kind: "node", id: "nginx" });
  });

  it("activates an Unplaced entity the graph still contains", async () => {
    const { onSelect } = renderNavigator();

    await fireEvent.click(
      screen.getByRole("button", { name: "host-7, no segment" }),
    );

    expect(onSelect).toHaveBeenCalledWith({
      kind: "node",
      id: PLACEMENT_ISSUE_ENTITY_ID,
    });
  });

  it("offers no activation for an entity the graph does not contain", async () => {
    const { container, onSelect } = renderNavigator();
    const missing = unplacedRow(container, MISSING_REFERENCE_ID)!;

    expect(missing.getAttribute("data-navigator-selectable")).toBe("false");
    expect(missing.tagName).toBe("DIV");
    expect(missing.textContent).toContain("missing host");

    await fireEvent.click(missing);

    expect(onSelect).not.toHaveBeenCalled();
  });

  it("marks the selected entity for assistive technology", () => {
    renderNavigator("web-1");

    expect(screen.getByRole("button", { name: "Host web-1" })).toHaveAttribute(
      "aria-current",
      "true",
    );
    expect(
      screen.getByRole("button", { name: "Host dns-1" }),
    ).not.toHaveAttribute("aria-current");
  });
});
