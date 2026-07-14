<script lang="ts">
  import type { IconName } from "./types";

  interface Props {
    name: IconName;
    size?: number;
  }

  let { name, size = 18 }: Props = $props();
</script>

<svg class="dashboard-icon" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
  {#if name === "shield"}<path d="M12 2 4 6v5c0 5 3.2 8.7 8 11 4.8-2.3 8-6 8-11V6Z"/><path d="m8.5 12 2.2 2.2 4.8-5"/>
  {:else if name === "search"}<circle cx="11" cy="11" r="7"/><path d="m16 16 5 5"/>
  {:else if name === "help"}<circle cx="12" cy="12" r="9"/><path d="M9.8 9a2.4 2.4 0 1 1 3.7 2c-1.2.7-1.5 1.2-1.5 2.2M12 17h.01"/>
  {:else if name === "bell"}<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>
  {:else if name === "chevron-down"}<path d="m7 9 5 5 5-5"/>
  {:else if name === "cursor"}<path d="m5 3 14 9-7 2-3 7Z"/>
  {:else if name === "link"}<path d="M10 13a5 5 0 0 0 7.5.5l2-2a5 5 0 0 0-7-7l-1.1 1.1M14 11a5 5 0 0 0-7.5-.5l-2 2a5 5 0 0 0 7 7l1.1-1.1"/>
  {:else if name === "server"}<rect x="3" y="4" width="18" height="7" rx="1"/><rect x="3" y="13" width="18" height="7" rx="1"/><path d="M7 7h.01M7 16h.01"/>
  {:else if name === "zone"}<path d="M17 18H7a5 5 0 1 1 1-9.9A7 7 0 0 1 21 12a4 4 0 0 1-4 6Z"/>
  {:else if name === "copy"}<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/>
  {:else if name === "trash"}<path d="M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13M10 11v5M14 11v5"/>
  {:else if name === "lock"}<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>
  {:else if name === "align"}<path d="M4 5h16M7 10h10M4 15h16M7 20h10"/>
  {:else if name === "tag"}<path d="M20 13 13 20 4 11V4h7Z"/><circle cx="8.5" cy="8.5" r="1"/>
  {:else if name === "play"}<path d="m8 5 11 7-11 7Z"/>
  {:else if name === "graph"}<circle cx="5" cy="12" r="2.5"/><circle cx="19" cy="6" r="2.5"/><circle cx="19" cy="18" r="2.5"/><path d="m7.3 11 9.4-4M7.3 13l9.4 4"/>
  {:else if name === "list"}<path d="M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01"/>
  {:else if name === "fit"}<path d="M8 3H3v5M16 3h5v5M8 21H3v-5M16 21h5v-5"/>
  {:else if name === "more"}<circle cx="5" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="19" cy="12" r="1" fill="currentColor"/>
  {:else if name === "chevron-right"}<path d="m9 6 6 6-6 6"/>
  {:else if name === "minus"}<path d="M5 12h14"/>
  {:else}<path d="M12 5v14M5 12h14"/>{/if}
</svg>

<style>
  .dashboard-icon {
    display: block;
    flex: none;
    pointer-events: none;
    color: var(--dashboard-icon-color, inherit);
  }
</style>
