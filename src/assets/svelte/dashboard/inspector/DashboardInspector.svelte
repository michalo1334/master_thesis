<script lang="ts">
  import type { Selectable } from "../contract";
  import { inspectorFor } from "../graph/canvas/inspectorMappings";
  import type { EditableGraphDocument } from "../graph/EditableGraphDocument.svelte";
  import type { SimulationReportDocument } from "../simulation-report/SimulationReportDocument.svelte";

  export type WorkspaceDocument =
    EditableGraphDocument | SimulationReportDocument;

  interface Props {
    document: WorkspaceDocument | undefined;
  }

  let { document }: Props = $props();

  let selectable = $derived.by((): Selectable | undefined => {
    if (!document || document.kind !== "graph") return undefined;
    return document.selection;
  });

  let InspectorComponent = $derived(inspectorFor(selectable));
</script>

<InspectorComponent {selectable} />
