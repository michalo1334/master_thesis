import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import SplitButton from "./SplitButton.svelte";
import type { SplitButtonOption } from "./SplitButton.svelte";

const options: SplitButtonOption[] = [
  { id: "alpha", icon: "shield", title: "Alpha" },
  { id: "beta", icon: "search", title: "Beta" },
  { id: "gamma", icon: "help", title: "Gamma", disabled: true },
];

function renderSplitButton(
  overrides: Partial<{
    activeId: string | undefined;
    disabled: boolean;
    variant: "large" | "small";
  }> = {},
) {
  const onSelect = vi.fn();
  const result = render(SplitButton, {
    props: {
      options,
      onSelect,
      ...overrides,
    },
  });
  return { onSelect, ...result };
}

afterEach(cleanup);

describe("SplitButton", () => {
  it("shows the first option by default", () => {
    renderSplitButton();

    expect(screen.getByRole("button", { name: "Alpha" })).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "More options" }),
    ).toBeInTheDocument();
  });

  it("shows the option matching the activeId", () => {
    renderSplitButton({ activeId: "beta" });

    expect(screen.getByRole("button", { name: "Beta" })).toBeInTheDocument();
  });

  it("fires onSelect with the active option id when the main region is clicked", async () => {
    const { onSelect } = renderSplitButton({ activeId: "beta" });

    await fireEvent.click(screen.getByRole("button", { name: "Beta" }));

    expect(onSelect).toHaveBeenCalledWith("beta");
  });

  it("opens the menu and fires onSelect with the picked option id", async () => {
    const { onSelect } = renderSplitButton({ activeId: "alpha" });

    await fireEvent.click(screen.getByRole("button", { name: "More options" }));

    const gammaItem = await screen.findByRole("menuitem", { name: /Gamma/ });
    expect(gammaItem).toHaveAttribute("data-disabled");

    const betaItem = screen.getByRole("menuitem", { name: /Beta/ });
    await fireEvent.click(betaItem);

    expect(onSelect).toHaveBeenCalledWith("beta");
  });

  it("disables both regions when the disabled prop is set", () => {
    renderSplitButton({ disabled: true });

    expect(screen.getByRole("button", { name: "Alpha" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "More options" })).toBeDisabled();
  });

  it("does not fire onSelect when the main region is disabled", async () => {
    const { onSelect } = renderSplitButton({ disabled: true });

    await fireEvent.click(screen.getByRole("button", { name: "Alpha" }));

    expect(onSelect).not.toHaveBeenCalled();
  });

  it("keeps the menu available when only the active option is disabled", async () => {
    const { onSelect } = renderSplitButton({ activeId: "gamma" });

    expect(screen.getByRole("button", { name: "Gamma" })).toBeDisabled();
    await fireEvent.click(screen.getByRole("button", { name: "More options" }));
    await fireEvent.click(
      await screen.findByRole("menuitem", { name: /Alpha/ }),
    );

    expect(onSelect).toHaveBeenCalledWith("alpha");
  });

  it("renders in the small variant with the same behaviour", async () => {
    const { onSelect } = renderSplitButton({
      activeId: "beta",
      variant: "small",
    });

    const main = screen.getByRole("button", { name: "Beta" });
    expect(main).toBeInTheDocument();

    await fireEvent.click(main);

    expect(onSelect).toHaveBeenCalledWith("beta");
  });
});
