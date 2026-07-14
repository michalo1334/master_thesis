<script lang="ts">
  import Icon from "./Icon.svelte";
  import type { TopologyNode } from "./types";

  interface Props {
    node: TopologyNode;
    onClose: () => void;
  }

  let { node, onClose }: Props = $props();
</script>

<aside class="dashboard-inspector" id="dashboard-property-inspector" aria-label="Properties inspector">
  <div class="dashboard-inspector-head">
    <h2>Properties</h2>
    <button aria-label="Collapse properties inspector" aria-controls="dashboard-property-inspector" aria-expanded="true" onclick={onClose}><Icon name="chevron-right" /></button>
  </div>
  <div class="dashboard-selection-summary">
    <span class="dashboard-selection-glyph"><Icon name="server" size={21} /></span>
    <div><strong>{node.name}</strong><span>{node.kind} · selected</span></div>
  </div>
  <div class="dashboard-inspector-body">
    <section class="dashboard-property-section">
      <h3>Identity</h3>
      <label><span>Name</span><input value={node.name} aria-label="Asset name" /></label>
      <label><span>Address</span><input value={node.address} aria-label="Asset address" /></label>
      <label><span>Zone</span><select aria-label="Asset zone" value={node.zone}><option>{node.zone}</option><option>DMZ / VLAN 10</option><option>Data / VLAN 30</option></select></label>
    </section>
    <section class="dashboard-property-section">
      <h3>Security posture</h3>
      <dl class="dashboard-property-list">
        <div><dt>Risk rating</dt><dd><span class={["dashboard-risk-tag", node.critical && "critical"]}>{node.risk}</span></dd></div>
        <div><dt>Exposure</dt><dd>{node.exposure}</dd></div>
        <div><dt>Expected blast radius</dt><dd>{node.blastRadius}</dd></div>
      </dl>
    </section>
    <section class="dashboard-property-section">
      <h3>Ownership</h3>
      <label><span>Owner</span><input value={node.owner} aria-label="Asset owner" /></label>
    </section>
  </div>
</aside>

<style>
  .dashboard-inspector { grid-area: inspector; min-width: 0; display: flex; flex-direction: column; background: var(--ds-color-paper); border-left: 1px solid #adb8c6; box-shadow: -2px 0 7px #17243c0c; z-index: 2; overflow: hidden; }
  .dashboard-inspector-head { min-height: var(--ds-inspector-header-height); flex: none; padding: 0 var(--ds-space-2) 0 0.875rem; display: flex; align-items: center; border-bottom: 1px solid var(--ds-color-border); }
  .dashboard-inspector-head h2 { margin: 0; font-size: var(--ds-text-lg); }
  .dashboard-inspector-head button { margin-left: auto; width: 1.8125rem; height: 1.8125rem; border: 0; border-radius: var(--ds-radius-md); background: transparent; display: grid; place-items: center; }
  .dashboard-inspector-head button:hover { background: #edf1f5; }
  .dashboard-selection-summary { padding: var(--ds-space-3) 0.875rem; display: flex; gap: 0.625rem; align-items: center; border-bottom: 1px solid var(--ds-color-border-soft); }
  .dashboard-selection-glyph { width: 2.125rem; height: 2.125rem; display: grid; place-items: center; border-radius: var(--ds-radius-lg); background: #e7f0fc; color: #285c99; }
  .dashboard-selection-summary strong, .dashboard-selection-summary span { display: block; }
  .dashboard-selection-summary div > span { color: var(--ds-color-text-muted); font-size: var(--ds-text-xs); }
  .dashboard-inspector-body { min-height: 0; overflow: auto; padding-bottom: 1.25rem; }
  .dashboard-property-section { padding: 0.6875rem 0.875rem 0.8125rem; border-bottom: 1px solid var(--ds-color-border-soft); }
  .dashboard-property-section h3 { margin: 0 0 0.5625rem; color: #566479; font-size: var(--ds-text-xs); text-transform: uppercase; letter-spacing: 0.03125rem; }
  .dashboard-property-section label { display: grid; grid-template-columns: 5.125rem minmax(0, 1fr); align-items: center; gap: var(--ds-space-2); margin: 0.4375rem 0; color: #667386; font-size: var(--ds-text-xs); }
  .dashboard-property-section input, .dashboard-property-section select { min-width: 0; width: 100%; min-height: 1.8125rem; padding: var(--ds-space-1) 0.4375rem; border: 1px solid #b9c3cf; border-radius: var(--ds-radius-sm); background: var(--ds-color-paper); }
  .dashboard-property-list { margin: 0; }
  .dashboard-property-list > div { display: flex; justify-content: space-between; align-items: center; margin: 0.4375rem 0; color: #5e6b7f; }
  .dashboard-property-list dd { margin: 0; color: #233147; font-weight: 700; font-variant-numeric: tabular-nums; }
  .dashboard-risk-tag { display: inline-flex; align-items: center; min-height: 1.375rem; padding: 0 0.4375rem; border-radius: 0.625rem; color: #7b5418; background: #fff1d7; font-size: var(--ds-text-xs); font-weight: 600; }
  .dashboard-risk-tag.critical { color: #8d2c24; background: #fde9e7; }

  @media (max-width: 47.5em) {
    .dashboard-inspector {
      position: absolute;
      z-index: 40;
      inset: 0 0 0 auto;
      width: min(var(--ds-inspector-width), 90vw);
      max-width: 100%;
    }
  }
</style>
