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
    graph.parent_id ? (parentTitle ?? graph.parent_id) : "Root graph",
  );
</script>

<Inspector title="Graph">
  <InspectorField
    fields={[
      { label: "Title", value: graph.title },
      { label: "Tags", value: graph.tags.join(", ") || "None" },
      { label: "Parent", value: parent },
      { label: "Nodes", value: String(graph.nodes.length) },
      { label: "Edges", value: String(graph.edges.length) },
      { label: "Lock version", value: String(graph.lock_version) },
    ]}
  />
</Inspector>
