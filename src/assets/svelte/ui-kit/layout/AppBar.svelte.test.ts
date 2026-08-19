import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/svelte";
import AppBar from "./AppBar.svelte";

afterEach(cleanup);

describe("AppBar", () => {
  it("shows the save action without an inert account menu", () => {
    render(AppBar, {
      props: { onSave: vi.fn(), saveDisabled: false, isSaving: false },
    });

    expect(screen.getByRole("button", { name: "Save" })).toBeInTheDocument();
    expect(
      screen.queryByRole("menuitem", { name: "Profile" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("menuitem", { name: "Workspace settings" }),
    ).not.toBeInTheDocument();
    expect(
      screen.queryByRole("menuitem", { name: "Sign out" }),
    ).not.toBeInTheDocument();
  });
});
