import { describe, expect, it } from "vitest";
import { requiredFlows } from "./mission-feasibility";

describe("mission feasibility", () => {
  it("reads required flows", () => {
    expect(
      requiredFlows({
        required_flows: [
          { source_segment_id: "segment-1", target_service_id: "service-1" },
        ],
      }),
    ).toEqual([
      { source_segment_id: "segment-1", target_service_id: "service-1" },
    ]);
  });
});
