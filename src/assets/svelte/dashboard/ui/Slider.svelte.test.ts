import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import Slider from "./Slider.svelte";

afterEach(cleanup);

describe("Slider", () => {
  it("commits a valid manual value and exposes it through its label", async () => {
    const onchange = vi.fn();

    render(Slider, {
      props: {
        label: "Center gravity",
        value: 0.1,
        min: 0,
        max: 0.3,
        step: 0.1,
        onchange,
      },
    });

    const input = screen.getByRole("spinbutton", { name: "Center gravity" });
    expect(input).toHaveAttribute("min", "0");
    expect(input).toHaveAttribute("max", "0.3");
    expect(input).toHaveAttribute("step", "any");

    await fireEvent.input(input, { target: { value: "0.2" } });
    await fireEvent.change(input);

    expect(onchange).toHaveBeenCalledWith(0.2);
  });

  it("commits an in-range manual value that does not match the slider step", async () => {
    const onchange = vi.fn();

    render(Slider, {
      props: {
        label: "Simulation runs",
        value: 1,
        min: 1,
        max: 2_000,
        step: 1_000,
        onchange,
      },
    });

    const input = screen.getByRole("spinbutton", { name: "Simulation runs" });
    await fireEvent.input(input, { target: { value: "1000" } });
    await fireEvent.change(input);

    expect(onchange).toHaveBeenCalledWith(1_000);
    expect(input).toHaveValue(1_000);
    expect(screen.getByRole("slider")).toHaveAttribute("aria-valuenow", "1000");
  });

  it("increments by the configured step after a manual value", async () => {
    render(Slider, {
      props: {
        label: "Simulation runs",
        value: 1,
        min: 1,
        max: 2_000,
        step: 1_000,
      },
    });

    const input = screen.getByRole("spinbutton", { name: "Simulation runs" });
    await fireEvent.input(input, { target: { value: "1000" } });
    await fireEvent.change(input);

    const slider = screen.getByRole("slider");
    expect(input).toHaveValue(1_000);
    expect(slider).toHaveAttribute("aria-valuenow", "1000");

    await fireEvent.keyDown(slider, { key: "ArrowRight" });

    expect(slider).toHaveAttribute("aria-valuenow", "2000");
  });

  it("disables the manual entry with the slider", () => {
    render(Slider, {
      props: {
        label: "Center gravity",
        disabled: true,
      },
    });

    expect(
      screen.getByRole("spinbutton", { name: "Center gravity" }),
    ).toBeDisabled();
  });
});
