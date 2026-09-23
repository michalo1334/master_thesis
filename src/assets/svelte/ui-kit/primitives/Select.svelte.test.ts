import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/svelte";
import Select from "./Select.svelte";

afterEach(cleanup);

const options = [
  { value: "alpha", label: "Alpha" },
  { value: "beta", label: "Beta" },
  { value: "gamma", label: "Gamma", disabled: true },
];

async function open(label: string): Promise<void> {
  await fireEvent.keyDown(screen.getByRole("button", { name: label }), {
    key: "Enter",
  });
}

describe("Select", () => {
  it("exposes its label and shows the placeholder when empty", () => {
    render(Select, {
      props: {
        label: "Foothold",
        options,
        placeholder: "Pick a host",
      },
    });

    const trigger = screen.getByRole("button", { name: "Foothold" });
    expect(trigger).toHaveTextContent("Pick a host");
  });

  it("reports the selected value and displays its label", async () => {
    const onchange = vi.fn();
    render(Select, {
      props: { label: "Foothold", options, onchange },
    });

    await open("Foothold");
    await fireEvent.pointerUp(
      await screen.findByRole("option", { name: "Beta" }),
    );

    expect(onchange).toHaveBeenCalledWith("beta");
    expect(screen.getByRole("button", { name: "Foothold" })).toHaveTextContent(
      "Beta",
    );
  });

  it("marks disabled options and keeps them unselectable", async () => {
    const onchange = vi.fn();
    render(Select, {
      props: { label: "Foothold", options, onchange },
    });

    await open("Foothold");
    const gamma = await screen.findByRole("option", { name: "Gamma" });
    expect(gamma).toHaveAttribute("aria-disabled", "true");

    await fireEvent.pointerUp(gamma);
    expect(onchange).not.toHaveBeenCalled();
  });

  it("disables the trigger", () => {
    render(Select, {
      props: { label: "Foothold", options, disabled: true },
    });

    expect(screen.getByRole("button", { name: "Foothold" })).toBeDisabled();
  });

  it("renders its content through a portal", async () => {
    const { container } = render(Select, {
      props: { label: "Foothold", options },
    });

    await open("Foothold");
    const content = await screen.findByRole("listbox");
    expect(container.contains(content)).toBe(false);
    expect(within(document.body).getByRole("listbox")).toBe(content);
  });
});
