import { describe, expect, it } from "vitest";
import { indexTopologyScene } from "../topology-scene-index";
import { buildTopologyFixture } from "./topology-test-fixture";
import {
  buildContextLinks,
  buildDrawnEntityIds,
  buildStructuralLinks,
  indexRunsEdges,
} from "./canvas-link-view-model";
import { buildTopologySpatialView } from "./canvas-spatial-view-model";
import { CONTEXT_SIZE, measureTopology, SERVICE_SIZE } from "./layout";
import { containsEdge, runsEdge } from "../__tests__/topology-fixtures";

const UNPLACED_CARD_HEIGHT = 46;

function fixtureView() {
  const fixture = buildTopologyFixture();
  const index = indexTopologyScene(fixture.scene);
  const spatial = buildTopologySpatialView(
    fixture.scene,
    index,
    measureTopology(fixture.scene),
    {
      serviceSize: SERVICE_SIZE,
      contextSize: CONTEXT_SIZE,
      unplacedCardHeight: UNPLACED_CARD_HEIGHT,
    },
  );
  return { ...fixture, index, spatial };
}

describe("canvas link view model", () => {
  it("uses projected host-service membership and matching authored Runs edges", () => {
    const { graph, index, spatial } = fixtureView();
    const runsEdges = indexRunsEdges([
      ...graph.edges,
      runsEdge("runs-stray", "dns-1", "nginx"),
    ]);

    const links = buildStructuralLinks(index, spatial.nodeRects, runsEdges, {
      edgePresentation: (edge) =>
        edge.type === "Runs"
          ? {
              color: "green",
              dashArray: "3 2",
              label: () => "Runs service",
            }
          : null,
      edgeAppearance: () => ({ stroke: "blue" }),
    });

    expect(links).toHaveLength(1);
    expect(links[0]).toMatchObject({
      edge: { id: "runs-nginx" },
      label: "Runs service",
      color: "green",
      dash: "3 2",
      appearance: { stroke: "blue" },
    });
    expect(
      buildStructuralLinks(index, spatial.nodeRects, indexRunsEdges([]), {
        edgePresentation: () => null,
      }),
    ).toEqual([]);
    expect(
      buildStructuralLinks(
        index,
        spatial.nodeRects,
        new Map([
          [
            "Runs:web-1:nginx",
            containsEdge("contains-invalid", "web-1", "nginx"),
          ],
        ]),
        { edgePresentation: () => null },
      ),
    ).toEqual([]);
  });

  it("builds only active, lens-visible attachment-anchor links", () => {
    const { scene, spatial } = fixtureView();
    const links = buildContextLinks(scene, {
      lensActive: true,
      visibleIds: new Set(["depl-cred"]),
      entityRects: spatial.entityRects,
      entityLabel: (node) => node.id,
    });

    expect(links).toEqual([
      expect.objectContaining({
        key: "depl-cred:stores-cred",
        attachmentId: "depl-cred",
        label: "StoresCredential anchor to web-1",
      }),
    ]);
    expect(
      buildContextLinks(scene, {
        lensActive: false,
        visibleIds: new Set(["depl-cred"]),
        entityRects: spatial.entityRects,
        entityLabel: (node) => node.id,
      }),
    ).toEqual([]);
  });

  it("keeps projected entities, attachments, and Unplaced floaters as drawn IDs", () => {
    const { scene, index, spatial } = fixtureView();

    expect(
      [
        ...buildDrawnEntityIds(
          index.projectedEntityIds,
          scene.attachments.map((attachment) => attachment.id),
          spatial.unplacedFloaters,
        ),
      ].sort(),
    ).toEqual([
      "depl-cred",
      "dns-1",
      "host-7",
      "nginx",
      "orphan-svc",
      "segment-a",
      "web-1",
    ]);
  });
});
