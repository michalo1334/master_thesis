import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import Checkbox from "./Checkbox.svelte";

afterEach(cleanup);

describe("Checkbox", () => {
  it("renders the label and is initially unchecked", () => {
    render(Checkbox, { props: { label: "Enable feature" } });

    const checkbox = screen.getByRole("checkbox", { name: "Enable feature" });
    expect(checkbox).not.toBeChecked();
  });

  it("renders initially checked when checked is true", () => {
    render(Checkbox, { props: { label: "Enabled", checked: true } });

    expect(screen.getByRole("checkbox", { name: "Enabled" })).toBeChecked();
  });

  it("toggles on click and fires onchange", async () => {
    const onchange = vi.fn();

    render(Checkbox, {
      props: { label: "Toggle me", checked: false, onchange },
    });

    const checkbox = screen.getByRole("checkbox", { name: "Toggle me" });
    await fireEvent.click(checkbox);

    expect(onchange).toHaveBeenCalledWith(true);
    expect(checkbox).toBeChecked();

    await fireEvent.click(checkbox);

    expect(onchange).toHaveBeenCalledWith(false);
    expect(checkbox).not.toBeChecked();
  });

  it("does not toggle when disabled", async () => {
    const onchange = vi.fn();

    render(Checkbox, {
      props: { label: "Disabled", disabled: true, onchange },
    });

    const checkbox = screen.getByRole("checkbox", { name: "Disabled" });
    expect(checkbox).toBeDisabled();

    await fireEvent.click(checkbox);

    expect(onchange).not.toHaveBeenCalled();
  });
});
