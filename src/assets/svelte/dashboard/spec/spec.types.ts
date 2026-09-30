/** Shared prop types for the JSON specification dialog shell. */

export interface SpecListItem {
  id: string;
  title: string;
  meta?: string;
}

export interface SpecTab {
  value: string;
  label: string;
}

export interface SpecAction {
  label: string;
  disabled: boolean;
  onAction: () => void;
  variant?: "default" | "confirm";
}
