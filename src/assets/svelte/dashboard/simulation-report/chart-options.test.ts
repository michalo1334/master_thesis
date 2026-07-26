import { describe, expect, it } from "vitest";
import {
  actionSuccessOptions,
  cdfOptions,
  convergenceOptions,
  histogramOptions,
} from "./chart-options";

describe("simulation report chart options", () => {
  it("maps histogram buckets to labelled bars", () => {
    const option = histogramOptions([
      { lower_bound: 0, upper_bound: 2, count: 3 },
      { lower_bound: 2, upper_bound: 4, count: 5 },
    ]);

    expect(option).toMatchObject({
      aria: { enabled: true },
      xAxis: { data: ["0–2", "2–4"] },
      series: [{ type: "bar", data: [3, 5] }],
    });
  });

  it("maps CDF points to a probability line", () => {
    const option = cdfOptions([
      { compromised_hosts: 2, cumulative_probability: 0.4 },
    ]);

    expect(option).toMatchObject({
      aria: { enabled: true },
      yAxis: { min: 0, max: 1 },
      series: [{ type: "line", data: [[2, 0.4]] }],
    });
  });

  it("maps convergence points to a running-mean line", () => {
    const option = convergenceOptions([{ run: 3, mean_blast_radius: 2.5 }]);

    expect(option).toMatchObject({
      aria: { enabled: true },
      xAxis: { name: "Run" },
      series: [{ type: "line", data: [[3, 2.5]] }],
    });
  });

  it("compares attempted and successful actions", () => {
    const option = actionSuccessOptions([
      { action_type: "exploit", attempts: 8, successes: 3 },
    ]);

    expect(option).toMatchObject({
      aria: { enabled: true },
      xAxis: { data: ["exploit"] },
      series: [
        { name: "Attempts", data: [8] },
        { name: "Successful actions", data: [3] },
      ],
    });
  });
});
