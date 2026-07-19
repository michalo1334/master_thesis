<script lang="ts">
  import type { Selectable } from "./contract";
  import type { WorkspaceDocument } from "./workspace/WorkspaceDocument.svelte";
  import { inspectorFor } from "./canvas/inspectorMappings";

  interface Props {
    document: WorkspaceDocument | undefined;
  }

  let { document }: Props = $props();

  let selectable = $derived.by((): Selectable | undefined => {
    if (!document || document.kind !== "canvas") return undefined;
    return document.selection;
  });

  let InspectorComponent = $derived(inspectorFor(selectable));
</script>

<InspectorComponent {selectable} />
