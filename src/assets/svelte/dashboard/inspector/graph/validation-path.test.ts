import { describe, expect, it } from "vitest";
import { pathStartsWith, pathsEqual } from "./validation-path";

describe("validation paths", () => {
  it("compares segments instead of joined text", () => {
    const left = ["zone.edge", "item"];
    const right = ["zone", "edge.item"];

    expect(left.join(".")).toBe(right.join("."));
    expect(pathsEqual(left, right)).toBe(false);
  });

  it("matches only nested paths below the required-flows field", () => {
    expect(
      pathStartsWith(
        ["required_flows", "1", "target_service_id"],
        ["required_flows"],
      ),
    ).toBe(true);
    expect(pathStartsWith(["required_flows_backup"], ["required_flows"])).toBe(
      false,
    );
  });
});
