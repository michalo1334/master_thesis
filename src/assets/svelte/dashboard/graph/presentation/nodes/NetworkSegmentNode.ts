import NetworkSegmentNodeStyle from "../../../inspector/network-segments/NetworkSegmentNodeStyle.svelte";
import NetworkSegmentNodeInfo from "../../../inspector/network-segments/NetworkSegmentNodeInfo.svelte";
import NetworkSegmentInspector from "../../../inspector/network-segments/NetworkSegmentInspector.svelte";

export const networkSegmentNode = {
  color: "var(--ui-color-accent)",
  glyph: NetworkSegmentNodeStyle,
  info: NetworkSegmentNodeInfo,
  inspector: NetworkSegmentInspector,
};
