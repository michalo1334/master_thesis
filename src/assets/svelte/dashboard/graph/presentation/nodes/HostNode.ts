import HostNodeStyle from "../../../inspector/hosts/HostNodeStyle.svelte";
import HostNodeInfo from "../../../inspector/hosts/HostNodeInfo.svelte";
import HostInspector from "../../../inspector/hosts/HostInspector.svelte";

export const hostNode = {
  color: "var(--ui-color-node-host)",
  glyph: HostNodeStyle,
  info: HostNodeInfo,
  inspector: HostInspector,
};
