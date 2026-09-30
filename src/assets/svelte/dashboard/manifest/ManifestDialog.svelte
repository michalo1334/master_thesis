<script lang="ts">
  import type { ManifestModel } from "./ManifestModel.svelte";
  import ManifestPreview from "./ManifestPreview.svelte";
  import type { SpecAction, SpecListItem, SpecTab } from "../spec/spec.types";
  import SpecDialog from "../spec/SpecDialog.svelte";
  import SpecEditor from "../spec/SpecEditor.svelte";
  import SpecVersionList from "../spec/SpecVersionList.svelte";

  interface Props {
    model: ManifestModel;
  }

  let { model }: Props = $props();

  const tabs: readonly SpecTab[] = [
    { value: "json", label: "JSON" },
    { value: "preview", label: "Preview" },
  ];

  const items = $derived<SpecListItem[]>(
    model.manifests.map((manifest) => ({
      id: manifest.id,
      title: manifest.title,
    })),
  );

  const actions = $derived<SpecAction[]>([
    {
      label: "Save",
      disabled: !model.canSave,
      onAction: () => void model.save(),
    },
    {
      label: "Start evaluation",
      disabled: !model.canStart,
      onAction: () => void model.start(),
      variant: "confirm",
    },
  ]);

  function handleOpenChange(open: boolean): void {
    if (!open) model.closeDialog();
  }
</script>

<SpecDialog
  open={model.open}
  onOpenChange={handleOpenChange}
  title="Evaluation manifests"
  description="Save and run reproducible evaluations from a raw JSON manifest."
>
  {#snippet list()}
    <SpecVersionList
      heading="Saved manifests"
      addLabel="Add"
      {items}
      selectedId={model.selectedId}
      emptyMessage="No saved manifests."
      isBusy={model.isBusy}
      onAdd={() => model.addManifest()}
      onSelect={(id) => void model.selectManifest(id)}
    />
  {/snippet}

  {#snippet editor()}
    <SpecEditor
      titleLabel="Title"
      title={model.title}
      onTitleInput={(value) => (model.title = value)}
      editorLabel="Manifest JSON"
      editorText={model.editorText}
      onEditorInput={(value) => (model.editorText = value)}
      {tabs}
      activeTab={model.activeTab}
      onTabChange={(value) => model.changeTab(value)}
      tabsAriaLabel="Manifest views"
      errors={model.errors}
      statusMessage={model.statusMessage}
      isBusy={model.isBusy}
      {actions}
    >
      {#snippet tabContent(tab)}
        {#if tab === "preview"}
          <ManifestPreview
            content={model.previewContent}
            reply={model.previewReply}
            errors={model.previewReply?.errors ?? []}
            isLoading={model.isLoadingPreview}
            notice={model.previewNotice}
          />
        {/if}
      {/snippet}
    </SpecEditor>
  {/snippet}
</SpecDialog>
