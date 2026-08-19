import CredentialNodeStyle from "../../../inspector/credentials/CredentialNodeStyle.svelte";
import CredentialNodeInfo from "../../../inspector/credentials/CredentialNodeInfo.svelte";
import CredentialInspector from "../../../inspector/credentials/CredentialInspector.svelte";

export const credentialNode = {
  color: "var(--ui-color-warning)",
  glyph: CredentialNodeStyle,
  info: CredentialNodeInfo,
  inspector: CredentialInspector,
};
