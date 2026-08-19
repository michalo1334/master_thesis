<script lang="ts">
  interface Props {
    name: string;
    size?: number;
  }

  const iconClasses: Record<string, string> = {
    shield: "hero-shield-check",
    search: "hero-magnifying-glass",
    filter: "hero-funnel",
    help: "hero-question-mark-circle",
    cursor: "hero-cursor-arrow-rays",
    link: "hero-link",
    play: "hero-play",
    graph: "hero-share",
    "simulation-report": "hero-document-chart-bar",
    "graph-diff": "hero-arrows-right-left",
    "chevron-right": "hero-chevron-right",
    "chevron-down": "hero-chevron-down",
    plus: "hero-plus",
    "squares-2x2": "hero-squares-2x2",
    star: "hero-star",
    "star-filled": "hero-star-solid",
    folder: "hero-folder",
    trash: "hero-trash",
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
