<script lang="ts">
  import { onMount } from "svelte";
  import type { DashboardApi } from "../../dashboard-api";
  import Select from "../../../ui-kit/primitives/Select.svelte";

  let {
    revisionId,
    label,
    value,
    api,
    onchange,
    error = "",
  }: {
    revisionId: string;
    label: string;
    value: string;
    api: DashboardApi;
    onchange: (value: string) => void;
    error?: string;
  } = $props();

  type HostOption = { value: string; label: string };
  type Hosts = { options: HostOption[]; message: string };
  let request = $state<Promise<Hosts>>(
    Promise.resolve({ options: [], message: "" }),
  );

  onMount(() => {
    request = loadHosts();
  });

  async function loadHosts(): Promise<Hosts> {
    if (!revisionId) return { options: [], message: "" };
    try {
      const reply = await api.openGraph(revisionId);
      if (reply.status === "ok")
        return {
          options:
            reply.graph?.nodes.flatMap((node) =>
              node.type === "Host"
                ? [{ value: node.id, label: node.data.name }]
                : [],
            ) ?? [],
          message: "",
        };
    } catch {}
    return { options: [], message: "Could not load Hosts for this revision." };
  }
</script>

{#snippet chooseHost(options: HostOption[], disabled: boolean)}
  <Select {label} {options} {value} {disabled} {onchange} {error} />
{/snippet}

{#await request}
  {@render chooseHost([], true)}
{:then hosts}
  {@render chooseHost(hosts.options, !hosts.options.length)}
  {#if hosts.message}<p role="status">{hosts.message}</p>{/if}
{/await}
