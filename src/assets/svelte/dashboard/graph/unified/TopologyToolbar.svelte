<script lang="ts">
  import type { Node } from "../../../contracts.generated/graph";
  import { DropdownMenu } from "bits-ui";
  import Icon from "../../../ui-kit/primitives/Icon.svelte";
  import type { TopologyScene } from "../topology-scene";
  import { TOPOLOGY_NODE_TYPES } from "./topology-node-types";
  import { searchTopology } from "./topology-search";

  interface Props {
    /** Scene that search reads. Search never changes graph placement. */
    scene: TopologyScene;
    /** True when the document allows graph edits. */
    editable?: boolean;
    onAdd?: (type: Node["type"]) => void;
    onSearchSelect: (entityId: string) => void;
    onArrange: () => void;
    onFit: () => void;
    onReset: () => void;
    pinnedCount?: number;
    onClearPins?: () => void;
    unplacedCount?: number;
    unplacedOpen?: boolean;
    onToggleUnplaced?: () => void;
  }

  let {
    scene,
    editable = false,
    onAdd = undefined,
    onSearchSelect,
    onArrange,
    onFit,
    onReset,
    pinnedCount = 0,
    onClearPins = undefined,
    unplacedCount = 0,
    unplacedOpen = false,
    onToggleUnplaced = undefined,
  }: Props = $props();

  /** Unique prefix for the combobox listbox and option ids. */
  const searchId = $props.id();

  let toolbarElement: HTMLDivElement;
  let searchElement: HTMLDivElement;
  let searchInput: HTMLInputElement;

  let query = $state("");
  /** True while the suggestion list is open. */
  let open = $state(false);
  /** Highlighted result, or -1 when no result is highlighted. */
  let activeIndex = $state(-1);
  /**
   * Control that owns the single toolbar tab stop.
   *
   * A toolbar is one tab stop. Arrow keys move between its controls, and Tab
   * leaves the whole group. `undefined` means the user has not activated a
   * control yet, so the first control holds the stop.
   */
  let focusKey = $state<string>();

  let showsAdd = $derived(editable && Boolean(onAdd));
  let showsClearPins = $derived(pinnedCount > 0 && Boolean(onClearPins));
  let showsUnplaced = $derived(unplacedCount > 0 && Boolean(onToggleUnplaced));
  /** Toolbar controls in DOM order. Keep in step with the markup below. */
  let itemKeys = $derived([
    ...(showsAdd ? ["add"] : []),
    "search",
    "arrange",
    "fit",
    "reset",
    ...(showsClearPins ? ["clear-pins"] : []),
    ...(showsUnplaced ? ["unplaced"] : []),
  ]);
  let focusTarget = $derived(
    itemKeys.includes(focusKey ?? "") ? focusKey : itemKeys[0],
  );

  let results = $derived(query.trim() ? searchTopology(scene, query) : []);
  let showResults = $derived(open && results.length > 0);
  let listboxId = `${searchId}-results`;
  let activeOptionId = $derived(
    results[activeIndex] ? optionId(activeIndex) : undefined,
  );
  /** Result count and no-match text, announced while the list is open. */
  let status = $derived.by(() => {
    if (!open || !query.trim()) return { visible: false, text: "" };
    if (results.length === 0)
      return { visible: true, text: "No matching entities" };
    return {
      visible: false,
      text: `${results.length} matching ${results.length === 1 ? "entity" : "entities"}`,
    };
  });

  function optionId(index: number): string {
    return `${searchId}-option-${index}`;
  }

  function tabindexOf(key: string): 0 | -1 {
    return focusTarget === key ? 0 : -1;
  }

  /** Toolbar control the event target belongs to. */
  function toolbarKeyOf(target: EventTarget | null): string | undefined {
    if (!(target instanceof Element)) return undefined;
    return target.closest<HTMLElement>("[data-toolbar-key]")?.dataset
      .toolbarKey;
  }

  function handleToolbarFocusIn(event: FocusEvent): void {
    const key = toolbarKeyOf(event.target);
    if (key) focusKey = key;
  }

  /**
   * Moves focus between the toolbar controls.
   *
   * Home and End reach the first and last control. Arrow keys wrap. A control
   * that unmounts, such as Clear pins, loses the tab stop instead of leaving
   * the toolbar unreachable: `focusTarget` falls back to the first control.
   */
  function handleToolbarKeydown(event: KeyboardEvent): void {
    // A text field inside the toolbar owns its own arrow keys.
    if (event.defaultPrevented || event.target instanceof HTMLInputElement)
      return;
    const items = [
      ...(toolbarElement?.querySelectorAll<HTMLElement>("[data-toolbar-key]") ??
        []),
    ];
    if (items.length === 0) return;

    const index = items.findIndex(
      (item) => item.dataset.toolbarKey === toolbarKeyOf(event.target),
    );
    let next: number;
    switch (event.key) {
      case "ArrowRight":
      case "ArrowDown":
        next = index < 0 ? 0 : (index + 1) % items.length;
        break;
      case "ArrowLeft":
      case "ArrowUp":
        next =
          index < 0
            ? items.length - 1
            : (index - 1 + items.length) % items.length;
        break;
      case "Home":
        next = 0;
        break;
      case "End":
        next = items.length - 1;
        break;
      default:
        return;
    }

    event.preventDefault();
    const item = items[next];
    if (!item) return;
    focusKey = item.dataset.toolbarKey;
    item.focus();
  }

  function addNode(type: Node["type"]): void {
    onAdd?.(type);
  }

  function handleSearchInput(event: Event): void {
    const value = (event.currentTarget as HTMLInputElement).value;
    query = value;
    const matches = value.trim() ? searchTopology(scene, value) : [];
    open = value.trim().length > 0;
    activeIndex = matches.length > 0 ? 0 : -1;
  }

  /** Moves the highlight and wraps at both ends of the result list. */
  function moveActive(step: number): void {
    if (results.length === 0) {
      open = false;
      activeIndex = -1;
      return;
    }
    open = true;
    const from =
      activeIndex < 0 ? (step > 0 ? -1 : results.length) : activeIndex;
    activeIndex = (from + step + results.length) % results.length;
  }

  function selectResult(entityId: string): void {
    query = "";
    open = false;
    activeIndex = -1;
    // The list unmounts and takes the option with it, so the text field keeps
    // focus and the user can search again.
    searchInput?.focus();
    onSearchSelect(entityId);
  }

  function handleSearchKeydown(event: KeyboardEvent): void {
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        moveActive(1);
        return;
      case "ArrowUp":
        event.preventDefault();
        moveActive(-1);
        return;
      case "Enter": {
        const result = results[activeIndex];
        if (!showResults || !result) return;
        event.preventDefault();
        selectResult(result.id);
        return;
      }
      case "Escape":
        event.preventDefault();
        // Escape dismisses the suggestion list first, then clears the query.
        if (open) {
          open = false;
          activeIndex = -1;
        } else {
          query = "";
        }
        return;
      default:
        return;
    }
  }

  /** Dismisses the suggestion list when the pointer acts outside it. */
  function handleWindowPointerDown(event: PointerEvent): void {
    if (!open) return;
    const target = event.target;
    if (target instanceof Node && searchElement?.contains(target)) return;
    open = false;
    activeIndex = -1;
  }
</script>

<svelte:window onpointerdown={handleWindowPointerDown} />

<!--
  A toolbar is one tab stop: its controls hold the tab stop, the container
  itself is never focusable.
-->
<!-- svelte-ignore a11y_interactive_supports_focus -->
<div
  class="topology-toolbar"
  role="toolbar"
  aria-label="Topology actions"
  aria-orientation="horizontal"
  bind:this={toolbarElement}
  onfocusin={handleToolbarFocusIn}
  onkeydown={handleToolbarKeydown}
>
  {#if showsAdd}
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        class="topology-toolbar-button topology-toolbar-add"
        aria-label="Add entity"
        data-toolbar-key="add"
        tabindex={tabindexOf("add")}
      >
        <Icon name="plus" size={16} />
        <span>Add</span>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          class="dashboard-menu-content topology-toolbar-menu"
          side="bottom"
          sideOffset={4}
          align="start"
        >
          {#each TOPOLOGY_NODE_TYPES as type (type)}
            <DropdownMenu.Item
              class="dashboard-menu-item"
              onclick={() => addNode(type)}>{type}</DropdownMenu.Item
            >
          {/each}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  {/if}

  <div class="topology-toolbar-search" bind:this={searchElement}>
    <input
      bind:this={searchInput}
      type="text"
      role="combobox"
      class="topology-toolbar-search-input"
      aria-label="Search topology"
      placeholder="Search…"
      autocomplete="off"
      data-toolbar-key="search"
      tabindex={tabindexOf("search")}
      bind:value={query}
      aria-expanded={showResults}
      aria-controls={showResults ? listboxId : undefined}
      aria-autocomplete="list"
      aria-activedescendant={showResults ? activeOptionId : undefined}
      oninput={handleSearchInput}
      onkeydown={handleSearchKeydown}
    />
    {#if showResults}
      <ul
        id={listboxId}
        class="topology-toolbar-results"
        role="listbox"
        aria-label="Search results"
      >
        {#each results as result, index (result.id)}
          <li>
            <button
              type="button"
              id={optionId(index)}
              role="option"
              tabindex="-1"
              class="topology-toolbar-result"
              aria-selected={index === activeIndex}
              data-search-entity={result.id}
              data-search-unplaced={result.unplaced ? "true" : undefined}
              aria-label={`${result.label}, ${result.path}`}
              onclick={() => selectResult(result.id)}
            >
              <span class="topology-toolbar-result-label">{result.label}</span>
              <span class="topology-toolbar-result-path">{result.path}</span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
    {#if status.visible}
      <p class="topology-toolbar-empty" role="status">{status.text}</p>
    {:else if status.text}
      <p class="topology-toolbar-status" role="status">{status.text}</p>
    {/if}
  </div>

  <button
    type="button"
    class="topology-toolbar-button"
    data-toolbar-key="arrange"
    tabindex={tabindexOf("arrange")}
    onclick={onArrange}>Arrange</button
  >
  <button
    type="button"
    class="topology-toolbar-button"
    data-toolbar-key="fit"
    tabindex={tabindexOf("fit")}
    onclick={onFit}>Fit</button
  >
  <button
    type="button"
    class="topology-toolbar-button"
    data-toolbar-key="reset"
    tabindex={tabindexOf("reset")}
    onclick={onReset}>Reset</button
  >

  {#if showsClearPins}
    <button
      type="button"
      class="topology-toolbar-button"
      data-toolbar-key="clear-pins"
      tabindex={tabindexOf("clear-pins")}
      aria-label={`Clear pins (${pinnedCount})`}
      onclick={onClearPins}>Clear pins</button
    >
  {/if}

  {#if showsUnplaced}
    <button
      type="button"
      class="topology-toolbar-button is-warning"
      data-toolbar-key="unplaced"
      tabindex={tabindexOf("unplaced")}
      data-toolbar-unplaced={unplacedCount}
      aria-pressed={unplacedOpen}
      aria-label={`Unplaced entities (${unplacedCount})`}
      onclick={onToggleUnplaced}
    >
      <span aria-hidden="true">&#9888;</span>
      <span aria-hidden="true">{unplacedCount}</span>
    </button>
  {/if}
</div>

<style>
  .topology-toolbar {
    position: relative;
    z-index: 4;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--ui-space-1);
    padding: var(--ui-space-1) var(--ui-space-2);
    border-bottom: 1px solid var(--ui-color-border);
    background: var(--ui-color-paper);
  }
  .topology-toolbar-button {
    display: inline-flex;
    align-items: center;
    gap: var(--ui-space-1);
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: transparent;
    color: var(--ui-color-text);
    font: inherit;
    font-size: var(--ui-text-sm);
  }
  .topology-toolbar-button:hover {
    background: var(--ui-color-accent-soft);
  }
  .topology-toolbar-button[aria-pressed="true"] {
    background: var(--ui-color-accent-soft);
    border-color: var(--ui-color-accent);
    font-weight: 700;
  }
  .topology-toolbar-button.is-warning {
    border-color: var(--ui-color-warning);
    background: var(--ui-color-warning-bg);
    color: var(--ui-color-warning-text);
  }
  .topology-toolbar-search {
    position: relative;
    flex: 0 1 16rem;
    min-width: 8rem;
  }
  .topology-toolbar-search-input {
    width: 100%;
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
    font: inherit;
    font-size: var(--ui-text-sm);
  }
  .topology-toolbar-results,
  .topology-toolbar-empty {
    position: absolute;
    top: calc(100% + 2px);
    left: 0;
    z-index: 5;
    min-width: 100%;
    max-height: 15rem;
    overflow: auto;
    margin: 0;
  }
  .topology-toolbar-results {
    padding: var(--ui-space-1);
    list-style: none;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
  }
  .topology-toolbar-empty {
    padding: var(--ui-space-2);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-md);
    color: var(--ui-color-text-muted);
    font-size: var(--ui-text-sm);
  }
  /* Result counts stay available to assistive technology only. */
  .topology-toolbar-status {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: -1px;
    padding: 0;
    overflow: hidden;
    border: 0;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  .topology-toolbar-result {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    width: 100%;
    min-height: var(--ui-control-height);
    padding: var(--ui-space-1) var(--ui-space-2);
    border: 0;
    border-radius: var(--ui-radius-sm);
    background: transparent;
    color: var(--ui-color-text);
    font: inherit;
    text-align: left;
  }
  .topology-toolbar-result:hover,
  .topology-toolbar-result[aria-selected="true"] {
    background: var(--ui-color-accent-soft);
  }
  .topology-toolbar-result-label {
    font-size: var(--ui-text-sm);
    font-weight: 700;
  }
  .topology-toolbar-result-path {
    color: var(--ui-color-text-muted);
    font: var(--ui-text-xs) var(--ui-font-mono);
  }
  :global(.topology-toolbar-menu) {
    z-index: 100;
  }
</style>
