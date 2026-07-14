<script lang="ts">
  import { Avatar, DropdownMenu } from "bits-ui";
  import Icon from "./Icon.svelte";

  interface Props {
    filename: string;
    userName: string;
  }

  let { filename, userName }: Props = $props();
  let initials = $derived(userName.split(/\s+/).map((part) => part[0]).slice(0, 2).join(""));
</script>

<header class="dashboard-appbar">
  <div class="dashboard-brand">
    <span class="dashboard-brand-mark"><Icon name="shield" size={16} /></span>
    <span>BlastShield</span>
  </div>
  <span class="dashboard-appbar-divider" aria-hidden="true"></span>
  <span class="dashboard-filename">{filename}</span>
  <span class="dashboard-saved">Saved 2 minutes ago</span>
  <div class="dashboard-app-actions">
    <button class="dashboard-app-icon" aria-label="Search"><Icon name="search" /></button>
    <button class="dashboard-app-icon" aria-label="Help"><Icon name="help" /></button>
    <button class="dashboard-app-icon" aria-label="Notifications"><Icon name="bell" /></button>
    <DropdownMenu.Root>
      <DropdownMenu.Trigger class="dashboard-avatar-trigger" aria-label={`Open account menu for ${userName}`}>
        <Avatar.Root class="dashboard-avatar">
          <Avatar.Fallback>{initials}</Avatar.Fallback>
        </Avatar.Root>
        <Icon name="chevron-down" size={13} />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content class="dashboard-menu-content" sideOffset={7} align="end">
          <DropdownMenu.Group aria-label="Account">
            <DropdownMenu.GroupHeading class="dashboard-menu-heading">{userName}</DropdownMenu.GroupHeading>
            <DropdownMenu.Item class="dashboard-menu-item">Profile</DropdownMenu.Item>
            <DropdownMenu.Item class="dashboard-menu-item">Workspace settings</DropdownMenu.Item>
          </DropdownMenu.Group>
          <DropdownMenu.Separator class="dashboard-menu-separator" />
          <DropdownMenu.Item class="dashboard-menu-item">Sign out</DropdownMenu.Item>
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

  .dashboard-brand { display: flex; align-items: center; gap: 0.5625rem; font-weight: 700; letter-spacing: .0125rem; white-space: nowrap; }
  .dashboard-brand-mark { width: var(--ds-space-6); height: var(--ds-space-6); display: grid; place-items: center; border-radius: 0.3125rem; background: #3b83e5; }
  .dashboard-appbar-divider { width: 1px; height: 1.25rem; background: #ffffff35; }
  .dashboard-filename { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-weight: 600; }
  .dashboard-saved { color: #b9c8dc; font-size: var(--ds-text-sm); white-space: nowrap; }
  .dashboard-app-actions { margin-left: auto; display: flex; align-items: center; gap: var(--ds-space-1); }
  /* Bits UI owns the trigger and avatar DOM, so these selectors cross that component boundary. */
  .dashboard-app-icon, .dashboard-appbar :global(.dashboard-avatar-trigger) { border: 0; border-radius: var(--ds-radius-md); color: var(--ds-color-on-dark); background: transparent; }
  .dashboard-app-icon { width: var(--ds-space-8); height: var(--ds-control-height); display: grid; place-items: center; }
  .dashboard-app-icon:hover, .dashboard-appbar :global(.dashboard-avatar-trigger:hover) { background: var(--ds-color-on-dark-hover); }
  .dashboard-appbar :global(.dashboard-avatar-trigger) { display: flex; align-items: center; gap: 0.1875rem; padding: 0.125rem var(--ds-space-1); }
  .dashboard-appbar :global(.dashboard-avatar) { width: var(--ds-avatar-size); height: var(--ds-avatar-size); display: grid; place-items: center; border-radius: 50%; color: var(--ds-color-nav); background: #d8e8ff; font-size: var(--ds-text-sm); font-weight: 700; }

  @media (max-width: 65.625em) {
    .dashboard-saved { display: none; }
  }

  @media (max-width: 47.5em) {
    .dashboard-appbar { padding-inline: var(--ds-space-2); }
    .dashboard-brand > span:last-child, .dashboard-saved { display: none; }
  }
</style>
