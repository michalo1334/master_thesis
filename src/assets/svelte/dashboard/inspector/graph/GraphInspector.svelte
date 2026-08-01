<script lang="ts">
  import type { LoadedGraph } from "../../contract";
  import Inspector from "../Inspector.svelte";
  import InspectorField from "../InspectorField.svelte";

  interface Props {
    graph: LoadedGraph;
    parentTitle?: string;
  }

  let { graph, parentTitle = undefined }: Props = $props();
  let parent = $derived(
    graph.parent_revision_id
      ? (parentTitle ?? graph.parent_revision_id)
      : "Root revision",
  );
</script>

<Inspector title="Graph">
  <InspectorField
    fields={[
      { label: "Title", value: graph.title },
      { label: "Graph ID", value: graph.id },
      { label: "Revision", value: graph.revision_id ?? "Unsaved" },
      { label: "Revision kind", value: graph.revision_kind ?? "Draft" },
      { label: "Revision number", value: String(graph.revision_number ?? 0) },
      { label: "Parent", value: parent },
      { label: "Nodes", value: String(graph.nodes.length) },
      { label: "Edges", value: String(graph.edges.length) },
    ]}
  />
</Inspector>
