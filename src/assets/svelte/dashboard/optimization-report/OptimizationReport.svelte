<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { OptimizationReportDocument } from "./OptimizationReportDocument.svelte";
  import KpiCards from "../simulation-report/KpiCards.svelte";
  import { formatOptimizationKpis } from "./optimization-report";
  import CvssStrategyPanel from "./strategy-panels/CvssStrategyPanel.svelte";
  import SimulationInformedStrategyPanel from "./strategy-panels/SimulationInformedStrategyPanel.svelte";
  import TopologySegmentationStrategyPanel from "./strategy-panels/TopologySegmentationStrategyPanel.svelte";
  import SimulatedAnnealingStrategyPanel from "./strategy-panels/SimulatedAnnealingStrategyPanel.svelte";

  interface Props {
    document: OptimizationReportDocument;
  }

  let { document }: Props = $props();
  let analysis = $derived(document.analysis);
  let activeTab = $state("overview");
  let hasCvssScores = $derived(
    document.reportData?.actions.some((action) => action.cvss_score != null) ??
      false,
  );
</script>

<article
  class="optimization-report"
  aria-labelledby="optimization-report-title"
>
  <header>
    <p>Optimization result</p>
    <h1 id="optimization-report-title">{document.title}</h1>
  </header>

  {#if document.status === "pending"}
    <section class="optimization-report-waiting" aria-live="polite">
      {#if document.totalSteps > 0}
        <progress max={document.totalSteps} value={document.completedSteps}
        ></progress>
        <span
          >{document.completedSteps} of {document.totalSteps} steps completed</span
        >
      {:else}
        <span class="optimization-report-spinner" aria-hidden="true"></span>
        <span
          >{document.phase ||
            "Optimization requested, waiting for progress..."}</span
        >
      {/if}
    </section>
  {:else if document.status === "error"}
    <section class="optimization-report-waiting">
      <p>{document.errorReason || "Optimization failed."}</p>
    </section>
  {:else}
    {#if document.reportData && analysis}
      <Tabs.Root
        class="optimization-report-tabs"
        orientation="vertical"
        value={activeTab}
        onValueChange={(value) => (activeTab = value)}
      >
        <Tabs.List
          class="optimization-report-tab-list"
          aria-label="Optimization report views"
        >
          <Tabs.Trigger class="optimization-report-tab" value="overview"
            >Overview</Tabs.Trigger
          >
          <Tabs.Trigger class="optimization-report-tab" value="defense-plan"
            >Defense plan</Tabs.Trigger
          >
          <Tabs.Trigger
            class="optimization-report-tab"
            value="strategy-analysis">Strategy analysis</Tabs.Trigger
          >
        </Tabs.List>

        <Tabs.Content class="optimization-report-tab-panel" value="overview">
          <KpiCards metrics={formatOptimizationKpis(document.reportData)} />

          {#if document.openOptimizedGraph}
            <button
              class="optimization-report-open"
              type="button"
              onclick={() => void document.openOptimizedGraph?.()}
            >
              Open optimized graph
            </button>
          {/if}
        </Tabs.Content>

        <Tabs.Content
          class="optimization-report-tab-panel"
          value="defense-plan"
        >
          <section
            class="optimization-report-section"
            aria-labelledby="defense-plan-title"
          >
            <h2 id="defense-plan-title">Defense plan</h2>
            {#if document.reportData.actions.length > 0}
              <div class="optimization-report-table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th scope="col">Action</th>
                      <th scope="col">Kind</th>
                      <th scope="col">Cost</th>
                      {#if hasCvssScores}<th scope="col">CVSS</th>{/if}
                    </tr>
                  </thead>
                  <tbody>
                    {#each document.reportData.actions as action (action.id)}
                      <tr>
                        <td>{action.label}</td>
                        <td>{action.kind}</td>
                        <td>{action.cost}</td>
                        {#if hasCvssScores}<td>{action.cvss_score ?? "—"}</td
                          >{/if}
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {:else}
              <p class="optimization-report-empty">
                No defenses were selected.
              </p>
            {/if}
          </section>
        </Tabs.Content>

        <Tabs.Content
          class="optimization-report-tab-panel"
          value="strategy-analysis"
        >
          {#if analysis.strategy === "cvss"}
            <CvssStrategyPanel {analysis} />
          {:else if analysis.strategy === "simulation_informed"}
            <SimulationInformedStrategyPanel {analysis} />
          {:else if analysis.strategy === "topology_segmentation"}
            <TopologySegmentationStrategyPanel {analysis} />
          {:else if analysis.strategy === "simulated_annealing"}
            <SimulatedAnnealingStrategyPanel {analysis} />
          {:else}
            <section
              class="optimization-report-section"
              aria-labelledby="unknown-strategy-title"
            >
              <h2 id="unknown-strategy-title">Strategy analysis unavailable</h2>
              <p class="optimization-report-empty">
                This report uses the unsupported strategy “{document.reportData
                  .strategy}”. Review its selected defenses in the Defense plan.
              </p>
            </section>
          {/if}
        </Tabs.Content>
      </Tabs.Root>
    {/if}
  {/if}
</article>

<style>
  .optimization-report {
    height: 100%;
    min-height: 0;
    overflow: auto;
    padding: var(--ds-space-6);
    background: var(--ds-color-surface);
  }
  header p,
  h1,
  .optimization-report-waiting p {
    margin: 0;
  }
  header p {
    color: var(--ds-color-accent);
    font-size: var(--ds-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  h1 {
    margin-top: var(--ds-space-1);
    font-size: 1.5rem;
  }
  .optimization-report-waiting {
    min-height: 16rem;
    margin-top: var(--ds-space-6);
    border: 2px dashed var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    color: var(--ds-color-text-secondary);
    display: grid;
    place-content: center;
    justify-items: center;
    gap: var(--ds-space-3);
  }
  progress {
    width: 18rem;
    accent-color: var(--ds-color-accent);
  }
  .optimization-report-spinner {
    width: 2rem;
    height: 2rem;
    border: 3px solid var(--ds-color-border);
    border-top-color: var(--ds-color-accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  .optimization-report-open {
    min-height: var(--ds-control-height);
    margin-top: var(--ds-space-5);
    padding: 0 var(--ds-space-3);
    border: 1px solid var(--ds-color-accent);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-accent);
    color: var(--ds-color-paper);
    font: inherit;
  }
  :global(.optimization-report-tabs) {
    display: grid;
    grid-template-columns: 9rem minmax(0, 1fr);
    gap: var(--ds-space-5);
    margin-top: var(--ds-space-6);
  }
  :global(.optimization-report-tab-list) {
    position: sticky;
    top: 0;
    display: grid;
    gap: var(--ds-space-1);
    padding: var(--ds-space-1);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    background: var(--ds-color-paper);
  }
  :global(.optimization-report-tab) {
    min-height: 2.5rem;
    padding: 0 var(--ds-space-3);
    border: 0;
    border-left: 3px solid transparent;
    border-radius: var(--ds-radius-sm);
    background: transparent;
    color: var(--ds-color-text-secondary);
    font: inherit;
    text-align: left;
  }
  :global(.optimization-report-tab[data-state="active"]) {
    border-left-color: var(--ds-color-accent);
    background: var(--ds-color-accent-soft);
    color: var(--ds-color-accent);
    font-weight: 700;
  }
  :global(.optimization-report-tab-panel) {
    min-width: 0;
  }
  .optimization-report-section {
    max-width: 62rem;
  }
  .optimization-report-section h2 {
    margin: 0 0 var(--ds-space-3);
    font-size: var(--ds-text-base);
  }
  .optimization-report-table-wrap {
    overflow-x: auto;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
  }
  table {
    width: 100%;
    border-collapse: collapse;
    text-align: left;
  }
  th,
  td {
    padding: var(--ds-space-3);
    border-bottom: 1px solid var(--ds-color-border);
  }
  th {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    text-transform: uppercase;
  }
  tbody tr:last-child td {
    border-bottom: 0;
  }
  .optimization-report-empty {
    margin: 0;
    color: var(--ds-color-text-secondary);
  }
  @media (max-width: 48em) {
    :global(.optimization-report-tabs) {
      grid-template-columns: minmax(0, 1fr);
      gap: var(--ds-space-4);
    }
    :global(.optimization-report-tab-list) {
      position: static;
      display: flex;
      padding: 0;
      overflow: hidden;
    }
    :global(.optimization-report-tab) {
      flex: 1;
      border-bottom: 3px solid transparent;
      border-left: 0;
      text-align: center;
    }
    :global(.optimization-report-tab[data-state="active"]) {
      border-bottom-color: var(--ds-color-accent);
    }
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
