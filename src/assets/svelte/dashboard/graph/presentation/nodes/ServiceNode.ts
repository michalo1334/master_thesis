import ServiceNodeStyle from "../../../inspector/services/ServiceNodeStyle.svelte";
import ServiceNodeInfo from "../../../inspector/services/ServiceNodeInfo.svelte";
import ServiceInspector from "../../../inspector/services/ServiceInspector.svelte";

export const serviceNode = {
  color: "var(--ds-color-node-service)",
  glyph: ServiceNodeStyle,
  info: ServiceNodeInfo,
  inspector: ServiceInspector,
};
