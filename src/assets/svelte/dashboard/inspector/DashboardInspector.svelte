<script lang="ts">
  import type { GraphSummary } from "../../contracts.generated/dashboard/graph";

  import type { WorkspaceDocument } from "../workspace/WorkspaceDocument.svelte";
  import { resolveInspector } from "./inspector-registry";

  interface Props {
    document: WorkspaceDocument | undefined;
    api: import("../dashboard-api").DashboardApi;
    summaries?: readonly GraphSummary[];
    onOpenParent?: (revisionId: string) => void;
  }

  let {
    document,
    api,
    summaries = [],
    onOpenParent = undefined,
  }: Props = $props();

  let request = $derived.by(() =>
    resolveInspector({
      document,
      api,
      summaries,
      onOpenParent,
    }),
  );
</script>

{#if request}
  {#if request.key !== undefined}
    {#key request.key}
      <request.Component {...request.props} />
    {/key}
  {:else}
    <request.Component {...request.props} />
  {/if}
{/if}
