<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { OptimizationReportDocument } from "./OptimizationReportDocument.svelte";
  import GraphDiff from "../graph/GraphDiff.svelte";
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
  let graphDiffLoadPending = $state(false);
  let isGraphDiffLoading = $derived(
    graphDiffLoadPending || document.graphDiffStatus === "loading",
  );
  let hasCvssScores = $derived(
    document.reportData?.actions.some((action) => action.cvss_score != null) ??
      false,
  );

  async function loadGraphDiff(): Promise<void> {
    if (document.graphDiff || isGraphDiffLoading) return;

    graphDiffLoadPending = true;
    try {
      await document.loadGraphDiff();
    } finally {
      graphDiffLoadPending = false;
    }
  }

  function handleTabChange(value: string): void {
    activeTab = value;
    if (value === "graph-diff") void loadGraphDiff();
  }
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
  {:else if document.status === "loading" || document.status === "ready" || document.status === "completed"}
    <section class="optimization-report-waiting" aria-live="polite">
      <span class="optimization-report-spinner" aria-hidden="true"></span>
      <span>Loading optimization report…</span>
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
        onValueChange={handleTabChange}
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
          <Tabs.Trigger class="optimization-report-tab" value="graph-diff"
            >Graph diff</Tabs.Trigger
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

        <Tabs.Content class="optimization-report-tab-panel" value="graph-diff">
          {#if document.graphDiff}
            <div class="optimization-report-graph-diff">
              <GraphDiff document={document.graphDiff} />
            </div>
          {:else}
            <section
              class="optimization-report-graph-diff-status"
              aria-live="polite"
            >
              {#if isGraphDiffLoading}
                <span class="optimization-report-spinner" aria-hidden="true"
                ></span>
                <p>Loading graph diff…</p>
              {:else if document.graphDiffStatus === "error"}
                <p>Unable to load graph diff.</p>
                <button type="button" onclick={() => void loadGraphDiff()}>
                  Retry
                </button>
              {:else}
                <p>Graph diff unavailable.</p>
              {/if}
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
    display: grid;
    grid-template-rows: auto minmax(0, 1fr);
    gap: var(--ui-space-6);
    overflow: hidden;
    padding: var(--ui-space-6);
    background: var(--ui-color-surface);
  }
  header p,
  h1,
  .optimization-report-waiting p {
    margin: 0;
  }
  header p {
    color: var(--ui-color-accent);
    font-size: var(--ui-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  h1 {
    margin-top: var(--ui-space-1);
    font-size: 1.5rem;
  }
  .optimization-report-waiting {
    min-height: 16rem;
    margin-top: var(--ui-space-6);
    border: 2px dashed var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    color: var(--ui-color-text-secondary);
    display: grid;
    place-content: center;
    justify-items: center;
    gap: var(--ui-space-3);
  }
  progress {
    width: 18rem;
    accent-color: var(--ui-color-accent);
  }
  .optimization-report-spinner {
    width: 2rem;
    height: 2rem;
    border: 3px solid var(--ui-color-border);
    border-top-color: var(--ui-color-accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  .optimization-report-open {
    min-height: var(--ui-control-height);
    margin-top: var(--ui-space-5);
    padding: 0 var(--ui-space-3);
    border: 1px solid var(--ui-color-accent);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-accent);
    color: var(--ui-color-paper);
    font: inherit;
  }
  :global(.optimization-report-tabs) {
    height: 100%;
    min-height: 0;
    display: grid;
    grid-template-columns: 9rem minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr);
    gap: var(--ui-space-5);
  }
  :global(.optimization-report-tab-list) {
    align-self: start;
    position: sticky;
    top: 0;
    display: grid;
    gap: var(--ui-space-1);
    padding: var(--ui-space-1);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
  }
  :global(.optimization-report-tab) {
    min-height: 2.5rem;
    padding: 0 var(--ui-space-3);
    border: 0;
    border-left: 3px solid transparent;
    border-radius: var(--ui-radius-sm);
    background: transparent;
    color: var(--ui-color-text-secondary);
    font: inherit;
    text-align: left;
  }
  :global(.optimization-report-tab[data-state="active"]) {
    border-left-color: var(--ui-color-accent);
    background: var(--ui-color-accent-soft);
    color: var(--ui-color-accent);
    font-weight: 700;
  }
  :global(.optimization-report-tab-panel) {
    min-width: 0;
    min-height: 0;
    overflow: auto;
  }
  .optimization-report-graph-diff {
    height: 100%;
    min-height: 0;
  }
  .optimization-report-graph-diff-status {
    min-height: 16rem;
    display: grid;
    place-content: center;
    justify-items: center;
    gap: var(--ui-space-3);
    border: 2px dashed var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    color: var(--ui-color-text-secondary);
  }
  .optimization-report-graph-diff-status p {
    margin: 0;
  }
  .optimization-report-graph-diff-status button {
    min-height: var(--ui-control-height);
    padding: 0 var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
    background: var(--ui-color-paper);
    color: inherit;
    font: inherit;
  }
  .optimization-report-section {
    max-width: 62rem;
  }
  .optimization-report-section h2 {
    margin: 0 0 var(--ui-space-3);
    font-size: var(--ui-text-base);
  }
  .optimization-report-table-wrap {
    overflow-x: auto;
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-lg);
    background: var(--ui-color-paper);
  }
  table {
    width: 100%;
    border-collapse: collapse;
    text-align: left;
  }
  th,
  td {
    padding: var(--ui-space-3);
    border-bottom: 1px solid var(--ui-color-border);
  }
  th {
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-xs);
    text-transform: uppercase;
  }
  tbody tr:last-child td {
    border-bottom: 0;
  }
  .optimization-report-empty {
    margin: 0;
    color: var(--ui-color-text-secondary);
  }
  @media (max-width: 48em) {
    :global(.optimization-report-tabs) {
      grid-template-columns: minmax(0, 1fr);
      grid-template-rows: auto minmax(0, 1fr);
      gap: var(--ui-space-4);
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
      border-bottom-color: var(--ui-color-accent);
    }
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
