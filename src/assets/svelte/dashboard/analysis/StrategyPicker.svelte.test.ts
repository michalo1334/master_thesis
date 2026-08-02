import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/svelte";
import StrategyPicker from "./StrategyPicker.svelte";
import type { OptimizationStrategy } from "../contract";

const options: { id: OptimizationStrategy; title: string }[] = [
  { id: "cvss", title: "CVSS" },
  { id: "simulation_informed", title: "Simulation-informed" },
  { id: "topology_segmentation", title: "Topology segmentation" },
  { id: "simulated_annealing", title: "Simulated annealing" },
];

afterEach(cleanup);

describe("StrategyPicker", () => {
  it("selects CVSS and disables foothold-dependent strategies without a foothold", async () => {
    const onchange = vi.fn();
    render(StrategyPicker, {
      props: {
        options,
        selectedStrategies: [],
        hasFoothold: false,
        onchange,
      },
    });

    const cvss = screen.getByRole("checkbox", { name: "CVSS" });
    expect(cvss).toBeEnabled();
    expect(
      screen.getByRole("checkbox", { name: "Simulation-informed" }),
    ).toBeDisabled();
    expect(
      screen.getByRole("checkbox", { name: "Topology segmentation" }),
    ).toBeDisabled();
    expect(
      screen.getByRole("checkbox", { name: "Simulated annealing" }),
    ).toBeDisabled();

    await fireEvent.click(cvss);

    expect(onchange).toHaveBeenCalledWith(["cvss"]);
  });
});
