import MissionCapabilityNodeStyle from "../../../inspector/mission-capabilities/MissionCapabilityNodeStyle.svelte";
import MissionCapabilityNodeInfo from "../../../inspector/mission-capabilities/MissionCapabilityNodeInfo.svelte";
import MissionCapabilityInspector from "../../../inspector/mission-capabilities/MissionCapabilityInspector.svelte";

export const missionCapabilityNode = {
  color: "var(--ds-color-node-mission-capability)",
  glyph: MissionCapabilityNodeStyle,
  info: MissionCapabilityNodeInfo,
  inspector: MissionCapabilityInspector,
};
