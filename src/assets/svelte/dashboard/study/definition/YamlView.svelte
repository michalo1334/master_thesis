<script lang="ts">
  let { yaml, filename }: { yaml: string; filename: string } = $props();
  let message = $state("");
  async function copy() {
    try {
      await navigator.clipboard.writeText(yaml);
      message = "YAML copied.";
    } catch {
      message = "Clipboard access failed. Use Download YAML.";
    }
  }
  function download() {
    const url = URL.createObjectURL(
      new Blob([yaml], { type: "application/yaml" }),
    );
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
    message = "YAML downloaded.";
  }
</script>

<section class="yaml-view" aria-label="Generated YAML">
  <header>
    <h3>Generated YAML · read-only</h3>
    <button type="button" onclick={copy}>Copy YAML</button><button
      type="button"
      onclick={download}>Download YAML</button
    >
  </header>
  <textarea readonly aria-label="Read-only YAML" value={yaml} rows={25}
  ></textarea>
  <p role="status">{message}</p>
</section>

<style>
  .yaml-view {
    position: sticky;
    top: var(--ui-space-3);
    min-width: 0;
    border: 1px solid var(--ui-color-border);
    background: var(--ui-color-paper);
    padding: var(--ui-space-3);
  }
  header {
    display: flex;
    gap: var(--ui-space-2);
    flex-wrap: wrap;
    align-items: center;
  }
  h3 {
    margin: 0;
    font-size: var(--ui-text-sm);
    flex: 1;
  }
  textarea {
    width: 100%;
    max-height: 65vh;
    resize: vertical;
    overflow: auto;
    font-size: var(--ui-text-xs);
    font-family: monospace;
    tab-size: 2;
    border: 0;
    background: var(--ui-color-paper);
    color: var(--ui-color-text);
  }
  p {
    margin: 0;
    font-size: var(--ui-text-sm);
  }
</style>
