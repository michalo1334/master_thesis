<script lang="ts">
  import type { IconName } from "../types";

  interface Props {
    name: IconName;
    size?: number;
  }

  const iconClasses: Record<IconName, string> = {
    shield: "hero-shield-check",
    search: "hero-magnifying-glass",
    help: "hero-question-mark-circle",
    bell: "hero-bell",
    "chevron-down": "hero-chevron-down",
    cursor: "hero-cursor-arrow-rays",
    link: "hero-link",
    server: "hero-server-stack",
    zone: "hero-cloud",
    copy: "hero-document-duplicate",
    trash: "hero-trash",
    lock: "hero-lock-closed",
    align: "hero-bars-3-bottom-left",
    tag: "hero-tag",
    play: "hero-play",
    graph: "hero-share",
    list: "hero-list-bullet",
    fit: "hero-arrows-pointing-out",
    more: "hero-ellipsis-horizontal",
    "chevron-right": "hero-chevron-right",
    minus: "hero-minus",
    plus: "hero-plus"
  };

  let { name, size = 18 }: Props = $props();
</script>

<span
  class={["dashboard-icon", iconClasses[name]]}
  style:--dashboard-icon-size={`${size}px`}
  aria-hidden="true"
></span>

<style>
  .dashboard-icon {
    display: block;
    flex: none;
    pointer-events: none;
    color: var(--dashboard-icon-color, inherit);
    width: var(--dashboard-icon-size);
    height: var(--dashboard-icon-size);
  }
</style>
