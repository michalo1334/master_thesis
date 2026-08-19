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
    padding: var(--ui-space-4);
    border: 1px solid var(--ui-color-border);
    border-radius: var(--ui-radius-lg);
    background: var(--ui-color-paper);
    box-shadow: var(--ui-shadow-sm);
  }
  h3,
  p {
    margin: 0;
  }
  h3 {
    color: var(--ui-color-text);
    font-size: var(--ui-text-base);
    font-weight: 700;
  }
  p {
    margin-top: var(--ui-space-1);
    color: var(--ui-color-text-secondary);
    font-size: var(--ui-text-sm);
    line-height: 1.4;
  }
  .statistical-chart-canvas {
    height: 15rem;
    margin-top: var(--ui-space-3);
  }

  @media (max-width: 34em) {
    .statistical-chart-canvas {
      height: 13.5rem;
    }
  }
</style>
