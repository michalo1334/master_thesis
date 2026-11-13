<script lang="ts">
  import { Tabs } from "bits-ui";
  import type { StudyDocument } from "./StudyDocument.svelte";
  import type { DashboardApi } from "../dashboard-api";
  import FilterableTable from "../../ui-kit/composites/FilterableTable.svelte";
  import DefinitionEditor from "./definition/DefinitionEditor.svelte";
  import FrozenDefinition from "./definition/FrozenDefinition.svelte";
  import ExecutionView from "./execution/ExecutionView.svelte";
  import { errorText } from "./StudyExecutionModel.svelte";
  let { document, api }: { document: StudyDocument; api: DashboardApi } =
    $props();
</script>

<article class="study-document" aria-label={document.title}>
  <header class="study-header">
    <div>
      <p>{document.isDraft ? "Editable draft" : "Frozen revision"}</p>
      <h1>{document.title}</h1>
    </div>
    <div class="study-actions">
      <button
        class="dashboard-action-button"
        type="button"
        onclick={() => void document.load()}>Refresh study</button
      >
      {#if !document.isDraft}<button
          class="dashboard-action-button"
          type="button"
          disabled={!document.detail}
          onclick={() => document.clone()}>Create revision from this</button
        >{/if}
    </div>
  </header>
  <Tabs.Root
    value={document.tab}
    onValueChange={(value) => {
      document.tab = value as "definition" | "executions";
      document.markRead();
    }}
  >
    <Tabs.List aria-label="Study sections"
      ><Tabs.Trigger value="definition">Definition</Tabs.Trigger><Tabs.Trigger
        value="executions"
        disabled={document.isDraft}
        >Executions: {document.executionTotal}</Tabs.Trigger
      ></Tabs.List
    >
    <Tabs.Content value="definition">
      {#if document.isDraft}<DefinitionEditor
          {document}
          {api}
          summaries={document.graphSummaries}
          onOpenGraph={(id) => document.openGraph(id)}
        />{:else}<FrozenDefinition {document} />{/if}
    </Tabs.Content>
    <Tabs.Content value="executions">
      <div class="study-actions history-actions">
        <button
          class="dashboard-action-button"
          type="button"
          disabled={document.starting ||
            document.startUncertain ||
            document.loading}
          onclick={() => void document.start()}
          >{document.starting ? "Starting…" : "Start new Pilot"}</button
        >
        <button
          class="dashboard-action-button"
          type="button"
          onclick={() => void document.refreshExecutions()}
          >Refresh execution history</button
        >
      </div>
      <div class="execution-history">
        <FilterableTable
          items={document.executions}
          getKey={(e) => e.execution_id}
          columns={[
            {
              key: "execution",
              header: "Execution",
              getValue: (e) => e.execution_id,
              filterable: true,
            },
            {
              key: "started",
              header: "Started",
              getValue: (e) => new Date(e.started_at).toLocaleString(),
            },
            {
              key: "state",
              header: "State",
              getValue: (e) =>
                `${e.state.replaceAll("_", " ")}${document.executionModels.find((m) => m.executionId === e.execution_id)?.attention ? " · needs attention" : ""}`,
            },
            {
              key: "pilot",
              header: "Pilot outcome",
              getValue: (e) => e.pilot_outcome?.outcome ?? "Unavailable",
            },
            {
              key: "selection",
              header: "Final selection",
              getValue: (e) => e.selection?.candidate_id ?? "Unavailable",
            },
          ]}
          selectionMode="single"
          bind:selectedKeys={
            () =>
              document.selectedExecutionId
                ? [document.selectedExecutionId]
                : [],
            (keys) => {
              if (keys[0] && keys[0] !== document.selectedExecutionId)
                document.selectExecution(keys[0]);
            }
          }
          perPage={5}
          server={{
            totalCount: document.executionTotal,
            page: document.executionPage,
            onchange: (q) => void document.refreshExecutions(q.page),
          }}
          emptyMessage="No executions. Start a new Pilot."
          noMatchMessage="No matching executions."
        />
      </div>
      {#if document.selectedExecution}<ExecutionView
          model={document.selectedExecution}
          {document}
        />{/if}
    </Tabs.Content>
  </Tabs.Root>
  {#if document.message}<p role="status">{document.message}</p>{/if}
  {#if document.definition.error && !document.isDraft}<pre
      role="alert">{errorText(document.definition.error)}</pre>{/if}
</article>

<style>
  .study-document {
    height: 100%;
    min-height: 0;
    overflow: auto;
    padding: var(--ui-space-4);
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-4);
    color: var(--ui-color-text);
  }
  .study-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--ui-space-3);
    flex-wrap: wrap;
  }
  .study-header h1 {
    margin: 0;
    font-size: var(--ui-text-lg);
  }
  .study-header p {
    margin: 0;
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
  }
  .study-actions {
    display: flex;
    gap: var(--ui-space-2);
    align-items: center;
    flex-wrap: wrap;
  }
  .history-actions {
    margin-block: var(--ui-space-3);
  }
  .execution-history {
    min-height: 15rem;
    overflow: auto;
    margin-bottom: var(--ui-space-4);
  }
  .study-document :global([role="tablist"]) {
    display: flex;
    gap: var(--ui-space-2);
    margin-bottom: var(--ui-space-3);
  }
  .study-document :global([role="tab"]) {
    min-height: var(--ui-control-height);
    padding: var(--ui-space-2) var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-sm);
    background: transparent;
    color: var(--ui-color-text);
    font: var(--ui-text-lg) / var(--ui-line-height) var(--ui-font-ui);
  }
  .study-document :global([role="tab"]:disabled) {
    opacity: 0.55;
    cursor: default;
  }
  .study-document :global([role="tab"]:focus-visible) {
    outline: 2px solid var(--ui-color-focus);
    outline-offset: 2px;
  }
  .study-document :global([role="tab"][data-state="active"]) {
    border-bottom: 2px solid var(--ui-color-accent);
    font-weight: 600;
  }
  pre {
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
</style>
