<script lang="ts">
  interface Props {
    title: string;
  }

  let { title }: Props = $props();
</script>

<article class="simulation-report" aria-labelledby="simulation-report-title">
  <header class="simulation-report-header">
    <p class="simulation-report-eyebrow">Simulation result</p>
    <h1 id="simulation-report-title">{title}</h1>
  </header>

  <section class="simulation-report-empty" aria-label="No results yet">
    <p>
      No simulation results available. Run a simulation to populate this report.
    </p>
  </section>
</article>

<style>
  .simulation-report {
    height: 100%;
    overflow: auto;
    padding: var(--ds-space-6);
    color: var(--ds-color-text);
    background: var(--ds-color-surface);
  }
  .simulation-report-header {
    max-width: 62rem;
    margin-bottom: var(--ds-space-6);
  }
  .simulation-report-eyebrow {
    margin: 0;
    color: var(--ds-color-accent);
    font-size: var(--ds-text-xs);
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
  h1,
  p {
    margin: 0;
  }
  h1 {
    margin-top: var(--ds-space-1);
    font-size: 1.5rem;
    line-height: 1.2;
  }
  .simulation-report-empty {
    display: grid;
    place-content: center;
    min-height: 16rem;
    border: 2px dashed var(--ds-color-border);
    border-radius: var(--ds-radius-md);
    color: var(--ds-color-text-secondary);
    text-align: center;
  }
  .simulation-report-empty p {
    max-width: 20rem;
    font-size: var(--ds-text-sm);
  }
  @media (max-width: 48em) {
    .simulation-report {
      padding: var(--ds-space-4);
    }
  }
</style>
