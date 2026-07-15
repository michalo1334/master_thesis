<script lang="ts">
  import { ContextMenu } from "bits-ui";
  import type { Snippet } from "svelte";
  import Icon from "../controls/Icon.svelte";
  import {
    commandAvailable,
    commandDefinitions,
    executeCommand,
    type CommandContext,
    type CommandId,
    type SelectedTopologyObject,
  } from "./registry";

  interface Props {
    context: Omit<CommandContext, "source">;
    topologyObject: SelectedTopologyObject;
    children: Snippet;
  }

  let { context, topologyObject, children }: Props = $props();

  const commandIds: CommandId[] = [
    "run-simulation",
    "optimize-defense",
    "toggle-inspector",
    "select-topology-object",
    "clear-selection",
    "duplicate-selection",
    "remove-selection",
    "lock-selection",
    "align-selection",
  ];

  const menuContext = () => ({ ...context, source: "context-menu" as const });
  const available = (id: CommandId) => commandAvailable(id, menuContext());
  const runCommand = (id: CommandId) => executeCommand(id, menuContext());
</script>

<ContextMenu.Root>
  <ContextMenu.Trigger class="dashboard-document-placeholder">
    {@render children()}
  </ContextMenu.Trigger>
  <ContextMenu.Portal>
    <ContextMenu.Content class="dashboard-menu-content" sideOffset={6}>
      <ContextMenu.Group aria-label="Topology commands">
        <ContextMenu.GroupHeading class="dashboard-menu-heading"
          >Topology</ContextMenu.GroupHeading
        >
        {#each commandIds as id (id)}
          {@const command = commandDefinitions[id]}
          {#if id === "select-topology-object"}
            <ContextMenu.Item
              class="dashboard-menu-item"
              disabled={!available(id)}
              onclick={() =>
                executeCommand(id, menuContext(), { object: topologyObject })}
            >
              {#if command.icon}<Icon name={command.icon} size={16} />{/if}
              <span>{command.label}</span>
            </ContextMenu.Item>
          {:else}
            <ContextMenu.Item
              class="dashboard-menu-item"
              disabled={!available(id)}
              onclick={() => runCommand(id)}
            >
              {#if command.icon}<Icon name={command.icon} size={16} />{/if}
              <span>{command.label}</span>
            </ContextMenu.Item>
          {/if}
        {/each}
      </ContextMenu.Group>
    </ContextMenu.Content>
  </ContextMenu.Portal>
</ContextMenu.Root>
