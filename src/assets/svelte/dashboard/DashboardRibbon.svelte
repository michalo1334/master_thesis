<script lang="ts">
  import Button from "./controls/Button.svelte";
  import Icon from "./controls/Icon.svelte";
  import Ribbon from "./ribbon/Ribbon";
  import type {
    TopologyDocument,
    TopologyEditorState,
  } from "./workspace/model";

  interface Props {
    topology?: TopologyDocument;
    inspectorVisible: boolean;
    onEditorChange: (editor: TopologyEditorState) => void;
    onInspectorToggle: () => void;
    runSimulation: () => void;
    optimizeDefense: () => void;
  }

  let {
    topology,
    inspectorVisible,
    onEditorChange,
    onInspectorToggle,
    runSimulation,
    optimizeDefense,
  }: Props = $props();
  let editor = $derived(topology?.editor);

  function setTool(tool: "select" | "connect") {
    if (!editor) return;
    onEditorChange({
      ...editor,
      tool,
      connectionSourceId: undefined,
    });
  }
</script>

<Ribbon>
  <Ribbon.Tab title="Home">
    <Ribbon.Section title="Tools">
      <Button
        aria-pressed={editor?.tool === "select"}
        disabled={!editor}
        onclick={() => setTool("select")}
        ><Icon name="cursor" size={22} /><span>Select</span></Button
      >
      <Button
        aria-pressed={editor?.tool === "connect"}
        disabled={!editor}
        onclick={() => setTool("connect")}
        ><Icon name="link" size={22} /><span>Connect</span></Button
      >
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="Analyze">
    <Ribbon.Section title="Attack model">
      <Button disabled={!editor} onclick={runSimulation}
        ><Icon name="play" size={22} /><span>Simulate</span></Button
      >
      <Button disabled={!editor} onclick={optimizeDefense}
        ><Icon name="shield" size={22} /><span>Optimize</span></Button
      >
    </Ribbon.Section>
  </Ribbon.Tab>
  <Ribbon.Tab title="View">
    <Ribbon.Section title="Workspace">
      <Button
        aria-pressed={inspectorVisible}
        disabled={!editor}
        onclick={onInspectorToggle}
        ><Icon name="chevron-right" size={22} /><span>Inspector</span></Button
      >
    </Ribbon.Section>
  </Ribbon.Tab>
</Ribbon>
