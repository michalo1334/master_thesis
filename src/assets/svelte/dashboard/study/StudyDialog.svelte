<script lang="ts">
  import type { SpecAction, SpecListItem, SpecTab } from "../spec/spec.types";
  import SpecDialog from "../spec/SpecDialog.svelte";
  import SpecEditor from "../spec/SpecEditor.svelte";
  import SpecVersionList from "../spec/SpecVersionList.svelte";
  import type { StudyModel } from "./StudyModel.svelte";
  import StudyPreview from "./StudyPreview.svelte";
  import StudyRunPicker from "./StudyRunPicker.svelte";
  import StudyRunTab from "./StudyRunTab.svelte";

  interface Props {
    model: StudyModel;
  }

  let { model }: Props = $props();

  const tabs: readonly SpecTab[] = [
    { value: "json", label: "JSON" },
    { value: "preview", label: "Preview" },
    { value: "run", label: "Run" },
  ];

  const items = $derived<SpecListItem[]>(
    model.specifications.map((specification) => ({
      id: specification.id,
      title: specification.title,
      meta: `${specification.study_id} v${specification.specification_version}`,
    })),
  );

  const actions = $derived<SpecAction[]>([
    {
      label: "Save",
      disabled: !model.canSave,
      onAction: () => void model.save(),
    },
    {
      label: "Save as new version",
      disabled: !model.canSaveAsNewVersion,
      onAction: () => void model.saveAsNewVersion(),
    },
  ]);

  function handleOpenChange(open: boolean): void {
    if (!open) model.closeDialog();
  }

  function selectedRunId(): string | undefined {
    const tier = model.pickerTier;
    return tier ? model.selections[tier] : undefined;
  }
</script>

<SpecDialog
  open={model.open}
  onOpenChange={handleOpenChange}
  title="Study analysis"
  description="Save an immutable study specification, map each declared tier to one completed evaluation run, and run the pilot analysis."
>
  {#snippet list()}
    <SpecVersionList
      heading="Saved versions"
      addLabel="New"
      {items}
      selectedId={model.selectedId}
      emptyMessage="No saved study specifications."
      isBusy={model.isBusy}
      onAdd={() => model.addSpecification()}
      onSelect={(id) => void model.selectSpecification(id)}
    />
  {/snippet}

  {#snippet editor()}
    <SpecEditor
      titleLabel="Title"
      title={model.title}
      onTitleInput={(value) => model.setTitle(value)}
      editorLabel="Study JSON"
      editorText={model.editorText}
      onEditorInput={(value) => model.setEditorText(value)}
      {tabs}
      activeTab={model.activeTab}
      onTabChange={(value) => model.changeTab(value)}
      tabsAriaLabel="Study views"
      errors={model.errors}
      statusMessage={model.statusMessage}
      isBusy={model.isBusy}
      {actions}
    >
      {#snippet tabContent(tab)}
        {#if tab === "preview"}
          <StudyPreview
            content={model.previewContent}
            reply={model.previewReply}
            errors={model.previewReply?.errors ?? []}
            isLoading={model.isLoadingPreview}
            notice={model.previewNotice}
          />
        {:else if tab === "run"}
          <StudyRunTab {model} />
        {/if}
      {/snippet}
    </SpecEditor>
  {/snippet}
</SpecDialog>

<StudyRunPicker
  open={model.pickerOpen}
  tier={model.pickerTier ?? ""}
  runs={model.pickerRuns}
  selectedRunId={selectedRunId()}
  onOpenChange={(open) => {
    if (!open) model.closeRunPicker();
  }}
  onSelect={(runId) => {
    const tier = model.pickerTier;
    if (tier) model.selectRun(tier, runId);
  }}
/>
