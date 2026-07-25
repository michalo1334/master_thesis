import StoresCredentialInspector from "../../../inspector/edges/StoresCredentialInspector.svelte";

export const storesCredentialEdge = {
  color: "var(--ds-color-positive)",
  dashArray: "1 3" as string | null,
  inspector: StoresCredentialInspector,
};
