import type { Component } from "svelte";
import type Icon from "../controls/Icon.svelte";

export interface WorkspaceDocument {
  id: string;
  label(): string;
  icon(): typeof Icon;
}
