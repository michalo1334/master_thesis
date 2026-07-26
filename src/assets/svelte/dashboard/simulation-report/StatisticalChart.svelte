<script lang="ts">
  import { Chart } from "svelte-echarts";
  import type { EChartsOption } from "echarts";
  import { init } from "./echarts";

  interface Props {
    id: string;
    title: string;
    takeaway: string;
    ariaLabel: string;
    option: EChartsOption;
  }

  let { id, title, takeaway, ariaLabel, option }: Props = $props();
</script>

<article class="statistical-chart" aria-labelledby={`${id}-title`}>
  <header>
    <h3 id={`${id}-title`}>{title}</h3>
    <p>{takeaway}</p>
  </header>
  <div class="statistical-chart-canvas">
    <Chart {init} options={option} tabindex={0} aria-label={ariaLabel} />
  </div>
</article>

<style>
  .statistical-chart {
    min-width: 0;
    padding: var(--ds-space-4);
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-lg);
    background: var(--ds-color-paper);
    box-shadow: var(--ds-shadow-sm);
  }
  h3,
  p {
    margin: 0;
  }
  h3 {
    color: var(--ds-color-text);
    font-size: var(--ds-text-base);
    font-weight: 700;
  }
  p {
    margin-top: var(--ds-space-1);
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-sm);
    line-height: 1.4;
  }
  .statistical-chart-canvas {
    height: 15rem;
    margin-top: var(--ds-space-3);
  }

  @media (max-width: 34em) {
    .statistical-chart-canvas {
      height: 13.5rem;
    }
  }
</style>
