<script lang="ts">
  import type { Selectable } from "../../contract";
  import Inspector from "../Inspector.svelte";

  interface Field {
    path: string[];
    value: string | number | null | undefined;
  }

  interface Props {
    selectable: Selectable;
    onUpdate: (selectable: Selectable) => void;
  }

  let { selectable, onUpdate }: Props = $props();
  let fields = $derived(flatten(selectable.data));

  function flatten(value: object, path: string[] = []): Field[] {
    return Object.entries(value).flatMap(([key, entry]) =>
      entry && typeof entry === "object"
        ? flatten(entry, [...path, key])
        : [{ path: [...path, key], value: entry }],
    );
  }

  function label(path: string[]): string {
    return path.join(" · ").replaceAll("_", " ");
  }

  function optionsFor(path: string[]): string[] | undefined {
    const key = path.at(-1);
    if (key === "credential_type") return ["password", "ssh_key", "token"];
    if (key === "protocol")
      return selectable.type === "SegmentReachability"
        ? ["tcp", "udp", "any"]
        : ["tcp", "udp"];
    if (key === "required_privilege")
      return selectable.type === "StoresCredential"
        ? ["user", "administrator"]
        : ["none", "user", "administrator"];
    if (key === "granted_privilege") return ["user", "administrator"];
    if (key === "attack_vector")
      return ["network", "adjacent", "local", "physical"];
    if (key === "attack_complexity") return ["low", "high"];
    if (key === "privileges_required") return ["none", "low", "high"];
    if (key === "user_interaction") return ["none", "required"];
    if (key === "scope") return ["unchanged", "changed"];
    if (/impact$/.test(key ?? "")) return ["none", "low", "high"];
    return undefined;
  }

  function numeric(field: Field): boolean {
    return (
      typeof field.value === "number" ||
      /port|probability/.test(field.path.at(-1) ?? "")
    );
  }

  function update(field: Field, raw: string) {
    const data = $state.snapshot(selectable.data) as Record<string, unknown>;
    let target: Record<string, unknown> = data;
    for (const key of field.path.slice(0, -1))
      target = target[key] as Record<string, unknown>;
    const key = field.path.at(-1)!;
    target[key] =
      raw === "" && (field.value == null || /^port_(start|end)$/.test(key))
        ? null
        : numeric(field)
          ? raw === ""
            ? field.value
            : Number(raw)
          : raw;
    onUpdate({ ...selectable, data } as Selectable);
  }
</script>

<Inspector title={selectable.type}>
  <form
    class="editable-selection-fields"
    onsubmit={(event) => event.preventDefault()}
  >
    {#each fields as field (field.path.join("."))}
      {@const options = optionsFor(field.path)}
      <label>
        <span>{label(field.path)}</span>
        {#if options}
          <select
            value={String(field.value ?? "")}
            onchange={(event) => update(field, event.currentTarget.value)}
          >
            {#each options as option (option)}
              <option value={option}>{option.replaceAll("_", " ")}</option>
            {/each}
          </select>
        {:else}
          <input
            type={numeric(field) ? "number" : "text"}
            value={field.value ?? ""}
            step={numeric(field) ? "any" : undefined}
            onchange={(event) => update(field, event.currentTarget.value)}
          />
        {/if}
      </label>
    {/each}
  </form>
</Inspector>

<style>
  .editable-selection-fields {
    display: grid;
    gap: var(--ds-space-3);
  }
  label {
    display: grid;
    gap: var(--ds-space-1);
  }
  label span {
    color: var(--ds-color-text-secondary);
    font-size: var(--ds-text-xs);
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }
  input,
  select {
    min-height: var(--ds-control-height);
    min-width: 0;
    padding: 0.375rem 0.5rem;
    border: 1px solid var(--ds-color-border);
    border-radius: var(--ds-radius-sm);
    background: var(--ds-color-surface);
    color: var(--ds-color-text);
    font: inherit;
  }
  input:focus-visible,
  select:focus-visible {
    outline: 2px solid var(--ds-color-focus);
    outline-offset: 1px;
  }
</style>
