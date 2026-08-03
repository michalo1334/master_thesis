<script lang="ts">
  import { Avatar, DropdownMenu } from "bits-ui";
  import Icon from "../ui/Icon.svelte";

  interface Props {
    onSave: () => void;
    saveDisabled: boolean;
    isSaving: boolean;
  }

  let { onSave, saveDisabled, isSaving }: Props = $props();
</script>

<header class="dashboard-appbar">
  <div class="dashboard-brand">
    <span class="dashboard-brand-mark"><Icon name="shield" size={16} /></span>
    <span>Blast Radius Simulator</span>
  </div>
  <span class="dashboard-appbar-divider" aria-hidden="true"></span>
  <div class="dashboard-app-actions">
    <button
      class="dashboard-app-save"
      type="button"
      onclick={onSave}
      disabled={saveDisabled}
      aria-busy={isSaving}>Save</button
    >
    <button class="dashboard-app-icon" aria-label="Search"
      ><Icon name="search" /></button
    >
    <button class="dashboard-app-icon" aria-label="Help"
      ><Icon name="help" /></button
    >
    <DropdownMenu.Root>
      <DropdownMenu.Trigger class="dashboard-avatar-trigger">
        <Avatar.Root class="dashboard-avatar">
          <Avatar.Fallback>s</Avatar.Fallback>
        </Avatar.Root>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          class="dashboard-menu-content"
          sideOffset={7}
          align="end"
        >
          <DropdownMenu.Group aria-label="Account">
            <DropdownMenu.GroupHeading class="dashboard-menu-heading"
              >s</DropdownMenu.GroupHeading
            >
            <DropdownMenu.Item class="dashboard-menu-item"
              >Profile</DropdownMenu.Item
            >
            <DropdownMenu.Item class="dashboard-menu-item"
              >Workspace settings</DropdownMenu.Item
            >
          </DropdownMenu.Group>
          <DropdownMenu.Separator class="dashboard-menu-separator" />
          <DropdownMenu.Item class="dashboard-menu-item"
            >Sign out</DropdownMenu.Item
          >
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  </div>
</header>

<style>
  .dashboard-appbar {
    grid-area: appbar;
    display: flex;
    align-items: center;
    gap: var(--ds-space-3);
    padding: 0 0.875rem;
    color: var(--ds-color-on-dark);
    background: var(--ds-color-nav);
  }

  .dashboard-brand {
    display: flex;
    align-items: center;
    gap: 0.5625rem;
    font-weight: 700;
    letter-spacing: 0.0125rem;
    white-space: nowrap;
  }
  .dashboard-brand-mark {
    width: var(--ds-space-6);
    height: var(--ds-space-6);
    display: grid;
    place-items: center;
    border-radius: 0.3125rem;
    background: var(--ds-color-accent);
  }
  .dashboard-appbar-divider {
    width: 1px;
    height: 1.25rem;
    background: color-mix(in srgb, var(--ds-color-on-dark) 21%, transparent);
  }
  .dashboard-app-actions {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: var(--ds-space-1);
  }
  .dashboard-app-icon,
  .dashboard-app-save,
  .dashboard-appbar :global(.dashboard-avatar-trigger) {
    border: 0;
    border-radius: var(--ds-radius-md);
    color: var(--ds-color-on-dark);
    background: transparent;
  }
  .dashboard-app-icon {
    width: var(--ds-space-8);
    height: var(--ds-control-height);
    display: grid;
    place-items: center;
  }
  .dashboard-app-save {
    height: var(--ds-control-height);
    padding: 0 var(--ds-space-2);
    font-size: var(--ds-text-sm);
    font-weight: 600;
  }
  .dashboard-app-icon:hover,
  .dashboard-app-save:not(:disabled):hover,
  .dashboard-appbar :global(.dashboard-avatar-trigger:hover) {
    background: var(--ds-color-on-dark-hover);
  }
  .dashboard-app-save:disabled {
    opacity: 0.6;
  }
  .dashboard-appbar :global(.dashboard-avatar-trigger) {
    display: flex;
    align-items: center;
    gap: 0.1875rem;
    padding: 0.125rem var(--ds-space-1);
  }
  .dashboard-appbar :global(.dashboard-avatar) {
    width: var(--ds-avatar-size);
    height: var(--ds-avatar-size);
    display: grid;
    place-items: center;
    border-radius: 50%;
    color: var(--ds-color-nav);
    background: var(--ds-color-accent-soft);
    font-size: var(--ds-text-sm);
    font-weight: 700;
  }
  @media (max-width: 35rem) {
    .dashboard-brand > span:not(.dashboard-brand-mark),
    .dashboard-appbar-divider {
      display: none;
    }
  }
</style>
