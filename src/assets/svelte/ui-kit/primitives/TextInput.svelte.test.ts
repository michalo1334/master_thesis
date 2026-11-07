import { afterEach, describe, it, expect, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import TextInput from "./TextInput.svelte";
afterEach(cleanup);
describe("TextInput", () => {
  it("keeps exact decimal strings and incomplete edits", async () => {
    const onchange = vi.fn();
    render(TextInput, {
      label: "Exact seed",
      value: "9007199254740993",
      inputmode: "numeric",
      onchange,
    });
    const input = screen.getByRole("textbox", { name: "Exact seed" });
    expect(input).toHaveValue("9007199254740993");
    await fireEvent.input(input, { target: { value: "" } });
    expect(onchange).toHaveBeenCalledWith("");
    await fireEvent.input(input, { target: { value: "9007199254740995" } });
    expect(onchange).toHaveBeenLastCalledWith("9007199254740995");
  });
  it("links supplied errors to the control without changing its value", async () => {
    const { rerender } = render(TextInput, {
      label: "Count",
      value: "unfinished",
      error: "Use a whole number.",
    });
    const input = screen.getByRole("textbox", { name: "Count" });
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input).toHaveAccessibleDescription("Use a whole number.");
    expect(input).toHaveValue("unfinished");
    await rerender({ label: "Count", value: "unfinished", error: "" });
    expect(input).not.toHaveAttribute("aria-invalid");
    expect(input).not.toHaveAttribute("aria-describedby");
    expect(input).toHaveValue("unfinished");
  });
  it("supports accessible disabled fields", () => {
    render(TextInput, { label: "Identity", disabled: true });
    expect(screen.getByRole("textbox", { name: "Identity" })).toBeDisabled();
  });
});
