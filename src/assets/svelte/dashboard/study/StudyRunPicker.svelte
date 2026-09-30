<script lang="ts">
  import type { StudyTierRunSummary } from "../../contracts.generated/dashboard/evaluation";
  import OptionPickerDialog from "../../ui-kit/composites/OptionPickerDialog.svelte";
  import type { FilterableTableColumn } from "../../ui-kit/composites/FilterableTable.types";
  import { formatTimestamp } from "../format";

  interface Props {
    open: boolean;
    tier: string;
    runs: readonly StudyTierRunSummary[];
    selectedRunId?: string;
    onOpenChange: (open: boolean) => void;
    onSelect: (runId: string) => void;
  }

  let {
    open,
    tier,
    runs,
    selectedRunId = undefined,
    onOpenChange,
    onSelect,
  }: Props = $props();

  const columns: readonly FilterableTableColumn<StudyTierRunSummary>[] = [
    {
      key: "manifest",
      header: "Manifest",
      getValue: (run) => run.manifest_title ?? "—",
      filterable: true,
    },
    {
      key: "graph",
      header: "Graph",
      getValue: (run) => run.graph_title ?? "—",
      filterable: true,
    },
    {
      key: "completed",
      header: "Completed",
      getValue: (run) =>
        run.completed_at ? formatTimestamp(run.completed_at) : "—",
    },
    {
      key: "plans",
      header: "Plans",
      getValue: (run) => String(run.plan_count),
      align: "end",
    },
    {
      key: "trials",
      header: "Trials",
      getValue: (run) => String(run.trial_count),
      align: "end",
    },
  ];

  function confirm(items: StudyTierRunSummary[]): boolean {
    const [run] = items;
    if (!run) return false;
    onSelect(run.id);
    return true;
  }
</script>

<OptionPickerDialog
  {open}
  {onOpenChange}
  items={runs}
  title={tier ? `Completed runs for ${tier}` : "Completed runs"}
  description="Select one completed non-warm-up evaluation run for this tier."
  getKey={(run) => run.id}
  {columns}
  initialSelection={selectedRunId ? [selectedRunId] : []}
  searchPlaceholder="Search completed runs…"
  emptyMessage="No completed evaluation run qualifies for this tier."
  noMatchMessage="No completed run matches the search."
  onConfirm={confirm}
/>
