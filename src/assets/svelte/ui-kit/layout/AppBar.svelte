<script lang="ts">
  import Icon from "../primitives/Icon.svelte";

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
  .dashboard-app-save {
    height: var(--ds-control-height);
    padding: 0 var(--ds-space-2);
    border: 0;
    border-radius: var(--ds-radius-md);
    color: var(--ds-color-on-dark);
    background: transparent;
    font-size: var(--ds-text-sm);
    font-weight: 600;
  }
  .dashboard-app-save:not(:disabled):hover {
    background: var(--ds-color-on-dark-hover);
  }
  .dashboard-app-save:disabled {
    opacity: 0.6;
  }
  @media (max-width: 35rem) {
    .dashboard-brand > span:not(.dashboard-brand-mark),
    .dashboard-appbar-divider {
      display: none;
    }
  }
</style>
