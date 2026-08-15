import { describe, expect, it } from "vitest";
import {
  layoutHostCards,
  layoutZones,
  zoneCollisionRadius,
  type ZoneLayoutInput,
} from "./NetworkCanvasLayout";

const zones: ZoneLayoutInput[] = [
  {
    id: "expanded",
    position: { x: 100, y: 100 },
    radius: { x: 220, y: 150 },
    pinned: true,
  },
  {
    id: "nearby",
    position: { x: 140, y: 110 },
    radius: { x: 130, y: 72 },
  },
  {
    id: "nearby-2",
    position: { x: 180, y: 120 },
    radius: { x: 130, y: 72 },
  },
];

describe("layoutZones", () => {
  it("pins the expanded zone at its persisted position", () => {
    const positions = layoutZones(zones, []);

    expect(positions.get("expanded")).toEqual({ x: 100, y: 100 });
  });

  it("separates zone collision radii", () => {
    const positions = layoutZones(zones, []);
    const values = [...positions.entries()];

    for (let index = 0; index < values.length; index++) {
      for (let other = index + 1; other < values.length; other++) {
        const [id, position] = values[index]!;
        const [otherId, otherPosition] = values[other]!;
        const zone = zones.find((item) => item.id === id)!;
        const otherZone = zones.find((item) => item.id === otherId)!;
        expect(
          Math.hypot(
            position.x - otherPosition.x,
            position.y - otherPosition.y,
          ),
        ).toBeGreaterThanOrEqual(
          zoneCollisionRadius(zone) + zoneCollisionRadius(otherZone) - 0.01,
        );
      }
    }
  });

  it("does not mutate input positions", () => {
    const input = structuredClone(zones);

    layoutZones(input, [{ sourceId: "expanded", targetId: "nearby" }]);

    expect(input).toEqual(zones);
  });
});

describe("layoutHostCards", () => {
  it("uses each row's tallest card to avoid overlap", () => {
    const positions = layoutHostCards(
      { x: 0, y: 0 },
      [
        { id: "expanded", height: 120 },
        { id: "short", height: 52 },
        { id: "next-row", height: 52 },
      ],
      2,
    );

    const expanded = positions.get("expanded")!;
    const nextRow = positions.get("next-row")!;
    expect(nextRow.y - 26).toBeGreaterThanOrEqual(expanded.y + 60 + 14);
  });
});
