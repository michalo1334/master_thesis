<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { Snippet } from "svelte";
  import { setRibbonContext } from "./ribbon-context";

  interface Props {
    children: Snippet;
    tabDecorations?: Record<string, { color?: string; animate?: string }>;
  }

  let { children, tabDecorations = {} }: Props = $props();
  let selectedTab = $state<string>();

  interface RibbonTabEntry {
    title: () => string;
    value: string;
  }

  let tabs = $state<RibbonTabEntry[]>([]);

  setRibbonContext({
    registerTab: (tab) => {
      tabs = [...tabs, tab];
      selectedTab ??= tab.value;

      return () => {
        tabs = tabs.filter(({ value }) => value !== tab.value);

        if (selectedTab === tab.value) {
          selectedTab = tabs[0]?.value;
        }
      };
    },
  });
</script>

<nav class="dashboard-ribbon" aria-label="Editor ribbon">
  <Tabs.Root
    class="dashboard-ribbon-content"
    value={selectedTab}
    onValueChange={(value) => (selectedTab = value)}
    loop
  >
    <Tabs.List class="dashboard-ribbon-tabs" aria-label="Ribbon sections">
      {#each tabs as tab (tab.value)}
        {@const decoration = tabDecorations[tab.title()]}
        <span
          data-ribbon-animate={decoration?.animate}
          style={decoration?.color
            ? `--ribbon-tab-color: ${decoration.color}`
            : undefined}
        >
          <Tabs.Trigger class="dashboard-ribbon-tab" value={tab.value}
            >{tab.title()}</Tabs.Trigger
          >
        </span>
      {/each}
    </Tabs.List>
    {@render children()}
  </Tabs.Root>
</nav>

<style>
  .dashboard-ribbon {
    grid-area: ribbon;
    min-width: 0;
    background: var(--ui-color-paper);
    border-bottom: 1px solid var(--ui-color-border);
    box-shadow: var(--ui-shadow-sm);
    z-index: 3;
  }
  :global(.dashboard-ribbon-content) {
    min-height: 100%;
    display: grid;
    grid-template-rows: minmax(var(--ui-ribbon-tabs-height), auto) minmax(
        0,
        1fr
      );
    align-items: end;
    padding: 0 var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border-soft);
  }
  :global(.dashboard-ribbon-content .dashboard-ribbon-tabs) {
    grid-row: 1;
    grid-column: 1;
    display: flex;
    align-items: end;
    min-width: 0;
    overflow-x: auto;
  }
  :global(.dashboard-ribbon-content .dashboard-ribbon-tab) {
    flex: none;
    min-height: var(--ui-document-tab-height);
    padding: 0 0.9375rem;
    border: 0;
    border-bottom: 2px solid transparent;
    background: transparent;
    color: var(--ui-color-text-secondary);
  }
  :global(
    .dashboard-ribbon-content .dashboard-ribbon-tab[data-state="active"]
  ) {
    color: var(--ui-color-accent);
    border-bottom-color: var(--ui-color-accent);
    font-weight: 600;
  }
  :global(
    .dashboard-ribbon-content
      [data-ribbon-animate="pulse"]
      .dashboard-ribbon-tab
  ) {
    animation: ribbon-pulse 1.5s ease-in-out infinite;
    color: var(--ribbon-tab-color, inherit);
  }
  @keyframes ribbon-pulse {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.15;
    }
  }
  :global(.dashboard-ribbon-content .dashboard-ribbon-panel) {
    grid-row: 2;
    grid-column: 1 / -1;
    display: flex;
    min-width: 0;
    width: 100%;
    padding: 0.4375rem 0.625rem 0.3125rem;
    overflow: hidden;
  }
  :global(.dashboard-ribbon-content .dashboard-ribbon-group) {
    position: relative;
    display: flex;
    align-items: stretch;
    gap: 0.1875rem;
    padding: 0 0.625rem var(--ui-space-4);
    border-right: 1px solid var(--ui-color-border-soft);
  }
  :global(.dashboard-ribbon-content .dashboard-ribbon-group:first-child) {
    padding-left: 0.1875rem;
  }
  :global(.dashboard-ribbon-content .dashboard-ribbon-group-label) {
    position: absolute;
    inset: auto 0 0;
    text-align: center;
    color: var(--ui-color-text-faint);
    font-size: var(--ui-text-xs);
  }
  @supports selector(.dashboard-ribbon-group:has(.dashboard-button-small)) {
    :global(
      .dashboard-ribbon-content
        .dashboard-ribbon-group:has(.dashboard-button-small)
    ) {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      align-content: start;
    }
  }

  @media (max-width: 65.625em) {
    :global(.dashboard-ribbon-content .dashboard-ribbon-panel) {
      padding-block: 0.1875rem;
    }
    :global(.dashboard-ribbon-content .dashboard-ribbon-group) {
      padding-inline: 0.3125rem;
    }
    :global(.dashboard-ribbon-content .dashboard-button) {
      min-height: 2.4375rem;
      min-width: 2.6875rem;
    }
    :global(
      .dashboard-ribbon-content .dashboard-button > span:not(.dashboard-icon)
    ) {
      display: none;
    }
  }

  @media (max-width: 47.5em) {
    :global(.dashboard-ribbon-content) {
      padding-left: 0.3125rem;
    }
    :global(.dashboard-ribbon-content .dashboard-ribbon-tab) {
      padding-inline: 0.5625rem;
    }
    :global(.dashboard-ribbon-content .dashboard-ribbon-panel) {
      padding: 0.1875rem 0.3125rem;
    }
    :global(.dashboard-ribbon-content .dashboard-ribbon-group) {
      padding: 0 0.1875rem;
      border: 0;
    }
    :global(.dashboard-ribbon-content .dashboard-ribbon-group-label),
    :global(
      .dashboard-ribbon-content .dashboard-button > span:not(.dashboard-icon)
    ) {
      display: none;
    }
    :global(.dashboard-ribbon-content .dashboard-button),
    :global(.dashboard-ribbon-content .dashboard-button-small) {
      min-width: 2rem;
      width: 2rem;
      min-height: 2rem;
      padding: var(--ui-space-1);
      justify-content: center;
    }
  }

  @media (max-width: 35rem) {
    :global(.dashboard-ribbon-content .dashboard-ribbon-tab) {
      padding-inline: 0.3125rem;
    }
  }

  @media (forced-colors: active) {
    :global(
      .dashboard-ribbon-content .dashboard-ribbon-tab[data-state="active"]
    ) {
      outline: 2px solid Highlight;
    }
  }
</style>
