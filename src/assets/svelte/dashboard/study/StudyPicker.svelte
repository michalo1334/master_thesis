<script lang="ts">
  import { Dialog } from "bits-ui";
  import { onMount } from "svelte";
  import type { WorkspaceModel } from "../workspace/WorkspaceModel.svelte";
  import type { DashboardApi } from "../dashboard-api";
  import type { RevisionSummary } from "../../contracts.generated/dashboard/study";
  import FilterableTable from "../../ui-kit/composites/FilterableTable.svelte";
  import { errorText } from "./StudyExecutionModel.svelte";
  let { workspace, api }: { workspace: WorkspaceModel; api: DashboardApi } =
    $props();
  let revisions = $state.raw<RevisionSummary[]>([]);
  let selected = $state<string[]>([]);
  let total = $state(0);
  let page = $state(1);
  let search = $state("");
  let loading = $state(false);
  let message = $state("");
  let generation = 0;
  const key = (r: RevisionSummary) => JSON.stringify(r.revision);
  onMount(() => {
    void load();
    return () => {
      generation++;
    };
  });
  async function load(nextPage = page, query = search) {
    const current = ++generation;
    loading = true;
    try {
      const reply = await api.studyRequest("fetch_study_revisions", {
        query,
        limit: 10,
        offset: (nextPage - 1) * 10,
      });
      if (current !== generation) return;
      revisions = reply.revisions;
      total = reply.total ?? 0;
      page = nextPage;
      search = query;
      message = errorText(reply.error);
      selected = [];
    } catch {
      if (current === generation) message = "Could not load saved revisions.";
    } finally {
      if (current === generation) loading = false;
    }
  }
  function openSelected() {
    const item = revisions.find((r) => key(r) === selected[0]);
    if (item) {
      workspace.openStudy(item.revision);
      workspace.studyPickerOpen = false;
    }
  }
</script>

<Dialog.Root
  open={workspace.studyPickerOpen}
  onOpenChange={(open) => (workspace.studyPickerOpen = open)}
>
  <Dialog.Portal
    ><Dialog.Overlay class="study-picker-overlay" /><Dialog.Content
      class="study-picker"
    >
      <Dialog.Title>Studies</Dialog.Title><Dialog.Description
        >Open a saved revision or define a new revision.</Dialog.Description
      >
      <div class="study-picker-table">
        <FilterableTable
          items={revisions}
          columns={[
            {
              key: "study",
              header: "Study",
              getValue: (r) => r.revision.study_id,
              filterable: true,
            },
            {
              key: "revision",
              header: "Revision",
              getValue: (r) => String(r.revision.revision),
            },
            {
              key: "executions",
              header: "Executions",
              getValue: (r) => String(r.execution_count),
            },
            {
              key: "state",
              header: "Latest state",
              getValue: (r) =>
                r.latest_state?.replaceAll("_", " ") ?? "No executions",
            },
          ]}
          getKey={key}
          selectionMode="single"
          bind:selectedKeys={selected}
          perPage={10}
          server={{
            totalCount: total,
            page,
            onchange: (q) => void load(q.page, q.search),
          }}
          emptyMessage={loading ? "Loading revisions…" : "No saved revisions."}
          noMatchMessage="No matching revisions."
        />
      </div>
      <p role="status">{message}</p>
      <footer>
        <button
          type="button"
          onclick={() => {
            workspace.createStudyDraft();
            workspace.studyPickerOpen = false;
          }}>New study revision</button
        >
        <button
          type="button"
          disabled={!selected.length || loading}
          onclick={openSelected}>Open selected</button
        ><Dialog.Close>Close</Dialog.Close>
      </footer>
    </Dialog.Content></Dialog.Portal
  >
</Dialog.Root>

<style>
  :global(.study-picker-overlay) {
    position: fixed;
    inset: 0;
    background: color-mix(in srgb, var(--ui-color-nav) 45%, transparent);
    z-index: 60;
  }
  :global(.study-picker) {
    position: fixed;
    inset: 10vh 10vw;
    z-index: 61;
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
    padding: var(--ui-space-4);
    display: flex;
    flex-direction: column;
    gap: var(--ui-space-3);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-md);
  }
  .study-picker-table {
    flex: 1;
    min-height: 12rem;
    overflow: auto;
  }
  footer {
    display: flex;
    gap: var(--ui-space-3);
    justify-content: flex-end;
  }
</style>
