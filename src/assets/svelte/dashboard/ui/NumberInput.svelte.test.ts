import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import NumberInput from "./NumberInput.svelte";

afterEach(cleanup);

describe("NumberInput", () => {
  it("renders the label and default value", () => {
    render(NumberInput, { props: { label: "Count", value: 5 } });

    expect(screen.getByRole("spinbutton", { name: "Count" })).toHaveValue(5);
  });

  it("fires onchange with the new value", async () => {
    const onchange = vi.fn();

    render(NumberInput, {
      props: { label: "Count", value: 0, onchange },
    });

    const input = screen.getByRole("spinbutton", { name: "Count" });
    await fireEvent.input(input, { target: { value: "42" } });
    await fireEvent.change(input);

    expect(onchange).toHaveBeenCalledWith(42);
    expect(input).toHaveValue(42);
  });

  it("accepts values within min and max bounds", async () => {
    const onchange = vi.fn();

    render(NumberInput, {
      props: { label: "Count", value: 5, min: 0, max: 10, onchange },
    });

    const input = screen.getByRole("spinbutton", { name: "Count" });
    await fireEvent.input(input, { target: { value: "7" } });
    await fireEvent.change(input);

    expect(onchange).toHaveBeenCalledWith(7);
    expect(input).toHaveValue(7);
  });

  it("rolls back a value below the minimum", async () => {
    const onchange = vi.fn();

    render(NumberInput, {
      props: { label: "Count", value: 5, min: 2, onchange },
    });

    const input = screen.getByRole("spinbutton", { name: "Count" });
    await fireEvent.input(input, { target: { value: "1" } });
    await fireEvent.change(input);

    expect(onchange).not.toHaveBeenCalled();
    expect(input).toHaveValue(5);
  });

  it("rolls back a value above the maximum", async () => {
    const onchange = vi.fn();

    render(NumberInput, {
      props: { label: "Count", value: 5, max: 10, onchange },
    });

    const input = screen.getByRole("spinbutton", { name: "Count" });
    await fireEvent.input(input, { target: { value: "15" } });
    await fireEvent.change(input);

    expect(onchange).not.toHaveBeenCalled();
    expect(input).toHaveValue(5);
  });

  it("disables the input when disabled", () => {
    render(NumberInput, {
      props: { label: "Count", disabled: true },
    });

    expect(screen.getByRole("spinbutton", { name: "Count" })).toBeDisabled();
  });
});
