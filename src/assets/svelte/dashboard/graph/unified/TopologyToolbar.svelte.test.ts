import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import TopologyToolbar from "./TopologyToolbar.svelte";
import { buildTopologyFixture } from "./topology-test-fixture";

afterEach(cleanup);

function renderToolbar(
  overrides: Partial<{
    editable: boolean;
    pinnedCount: number;
    unplacedCount: number;
    unplacedOpen: boolean;
  }> = {},
) {
  const { scene } = buildTopologyFixture();
  const callbacks = {
    onAdd: vi.fn(),
    onSearchSelect: vi.fn(),
    onArrange: vi.fn(),
    onFit: vi.fn(),
    onReset: vi.fn(),
    onClearPins: vi.fn(),
    onToggleUnplaced: vi.fn(),
  };
  const result = render(TopologyToolbar, {
    props: {
      scene,
      editable: true,
      unplacedCount: 4,
      ...callbacks,
      ...overrides,
    },
  });
  return { ...callbacks, ...result };
}

function searchInput(): HTMLInputElement {
  return screen.getByRole("combobox", {
    name: "Search topology",
  }) as HTMLInputElement;
}

describe("TopologyToolbar", () => {
  it("offers no Add action without edit permission", () => {
    renderToolbar({ editable: false });

    expect(
      screen.queryByRole("button", { name: "Add entity" }),
    ).not.toBeInTheDocument();
  });

  it("creates the node type chosen from the Add menu", async () => {
    const { onAdd } = renderToolbar();

    await fireEvent.click(screen.getByRole("button", { name: "Add entity" }));
    await fireEvent.click(
      await screen.findByRole("menuitem", { name: "Service" }),
    );

    expect(onAdd).toHaveBeenCalledWith("Service");
  });

  it("selects a search result and clears the query", async () => {
    const { onSearchSelect } = renderToolbar();
    const input = searchInput();

    await fireEvent.input(input, { target: { value: "nginx" } });
    const result = await screen.findByRole("option", {
      name: "nginx, Zone A / web-1 / nginx",
    });

    await fireEvent.click(result);

    expect(onSearchSelect).toHaveBeenCalledWith("nginx");
    expect(input.value).toBe("");
  });

  it("announces the result count while the list is open", async () => {
    renderToolbar();

    await fireEvent.input(searchInput(), { target: { value: "-" } });

    expect(screen.getByRole("status")).toHaveTextContent("5 matching entities");
  });

  it("announces and shows that a query matches nothing", async () => {
    renderToolbar();

    await fireEvent.input(searchInput(), { target: { value: "zzz" } });

    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(screen.getByRole("status")).toHaveTextContent(
      "No matching entities",
    );
  });

  it("moves through results with arrow keys and selects with Enter", async () => {
    const { onSearchSelect } = renderToolbar();
    const input = searchInput();

    await fireEvent.input(input, { target: { value: "e" } });

    const options = screen.getAllByRole("option");
    expect(options[0]).toHaveTextContent("Zone A");
    expect(options[0]).toHaveAttribute("aria-selected", "true");

    await fireEvent.keyDown(input, { key: "ArrowDown" });

    expect(screen.getAllByRole("option")[1]).toHaveTextContent("web-1");
    expect(screen.getAllByRole("option")[1]).toHaveAttribute(
      "aria-selected",
      "true",
    );

    await fireEvent.keyDown(input, { key: "Enter" });

    expect(onSearchSelect).toHaveBeenCalledWith("web-1");
    expect(input.value).toBe("");
  });

  it("dismisses the list with Escape and clears the query on a second press", async () => {
    renderToolbar();
    const input = searchInput();

    await fireEvent.input(input, { target: { value: "-" } });
    expect(screen.getByRole("listbox")).toBeInTheDocument();

    await fireEvent.keyDown(input, { key: "Escape" });

    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(input.value).toBe("-");

    await fireEvent.keyDown(input, { key: "Escape" });

    expect(input.value).toBe("");
  });

  it("dismisses the list when the pointer acts outside the search", async () => {
    renderToolbar();
    const input = searchInput();

    await fireEvent.input(input, { target: { value: "-" } });
    expect(screen.getByRole("listbox")).toBeInTheDocument();

    await fireEvent.pointerDown(document.body);

    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(input.value).toBe("-");
  });

  it("keeps one toolbar tab stop and moves focus with arrow keys", async () => {
    renderToolbar();
    const arrange = screen.getByRole("button", { name: "Arrange" });
    const fit = screen.getByRole("button", { name: "Fit" });

    // The toolbar is one tab stop: only the current control is tabbable.
    expect(screen.getByRole("button", { name: "Add entity" })).toHaveAttribute(
      "tabindex",
      "0",
    );
    expect(arrange).toHaveAttribute("tabindex", "-1");

    await fireEvent.keyDown(arrange, { key: "ArrowRight" });

    expect(document.activeElement).toBe(fit);
    expect(fit).toHaveAttribute("tabindex", "0");
    expect(arrange).toHaveAttribute("tabindex", "-1");

    await fireEvent.keyDown(fit, { key: "Home" });

    expect(document.activeElement).toBe(
      screen.getByRole("button", { name: "Add entity" }),
    );
  });

  it("keeps one toolbar tab stop when the focused control unmounts", async () => {
    const { scene } = buildTopologyFixture();
    const base = {
      scene,
      editable: true,
      unplacedCount: 4,
      onAdd: vi.fn(),
      onSearchSelect: vi.fn(),
      onArrange: vi.fn(),
      onFit: vi.fn(),
      onReset: vi.fn(),
      onClearPins: vi.fn(),
      onToggleUnplaced: vi.fn(),
    };
    const { rerender } = render(TopologyToolbar, {
      props: { ...base, pinnedCount: 1 },
    });

    screen.getByRole("button", { name: "Clear pins (1)" }).focus();

    await rerender({ ...base, pinnedCount: 0 });

    // The focused control is gone, so the first control holds the tab stop.
    expect(
      screen.queryByRole("button", { name: "Clear pins (1)" }),
    ).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Add entity" })).toHaveAttribute(
      "tabindex",
      "0",
    );
  });

  it("runs viewport and layout commands", async () => {
    const { onArrange, onFit, onReset } = renderToolbar();

    await fireEvent.click(screen.getByRole("button", { name: "Arrange" }));
    await fireEvent.click(screen.getByRole("button", { name: "Fit" }));
    await fireEvent.click(screen.getByRole("button", { name: "Reset" }));

    expect(onArrange).toHaveBeenCalledOnce();
    expect(onFit).toHaveBeenCalledOnce();
    expect(onReset).toHaveBeenCalledOnce();
  });

  it("offers Clear pins only when pins exist", () => {
    renderToolbar({ pinnedCount: 0 });

    expect(
      screen.queryByRole("button", { name: "Clear pins (0)" }),
    ).not.toBeInTheDocument();
  });

  it("clears pins from the toolbar", async () => {
    const { onClearPins } = renderToolbar({ pinnedCount: 2 });

    await fireEvent.click(
      screen.getByRole("button", { name: "Clear pins (2)" }),
    );

    expect(onClearPins).toHaveBeenCalledOnce();
  });

  it("hides the Unplaced count when nothing is unplaced", () => {
    renderToolbar({ unplacedCount: 0 });

    expect(
      screen.queryByRole("button", { name: "Unplaced entities (0)" }),
    ).not.toBeInTheDocument();
  });

  it("reports and toggles the Unplaced tray state", async () => {
    const { onToggleUnplaced } = renderToolbar({
      unplacedCount: 4,
      unplacedOpen: true,
    });
    const button = screen.getByRole("button", {
      name: "Unplaced entities (4)",
    });

    expect(button).toHaveAttribute("aria-pressed", "true");

    await fireEvent.click(button);

    expect(onToggleUnplaced).toHaveBeenCalledOnce();
  });
});
