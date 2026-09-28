<script lang="ts">
  import type { ImportedStudyResultsDocument } from "./ImportedStudyResultsDocument.svelte";
  import StudyAnalysis from "./StudyAnalysis.svelte";

  interface Props {
    document: ImportedStudyResultsDocument;
  }

  let { document }: Props = $props();
  let modeLabel = $derived(
    document.analysis.metadata.command_mode === "study-pilot"
      ? "Pilot planning output"
      : "Final study output",
  );
</script>

<article
  class="imported-study-results"
  data-imported-study-results={document.id}
  tabindex="-1"
  aria-labelledby="imported-study-results-title"
>
  <header class="imported-study-results-header">
    <h1 id="imported-study-results-title">{document.title}</h1>
    <p class="imported-study-results-status" role="status">{modeLabel}</p>
  </header>
  <StudyAnalysis analysis={document.analysis} />
</article>

<style>
  .imported-study-results {
    height: 100%;
    min-height: 0;
    overflow: auto;
    overscroll-behavior: contain;
    padding: var(--ui-space-6);
    background: var(--ui-color-surface);
    color: var(--ui-color-text);
  }

  .imported-study-results-header {
    max-width: 62rem;
    margin-bottom: var(--ui-space-6);
  }

  h1,
  p {
    margin: 0;
  }

  h1 {
    font-size: 1.5rem;
    line-height: 1.2;
  }

  .imported-study-results-status {
    margin-top: var(--ui-space-2);
    color: var(--ui-color-text-secondary);
  }

  @media (max-width: 48em) {
    .imported-study-results {
      padding: var(--ui-space-4);
    }
  }
</style>
