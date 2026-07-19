import "svelte/elements";

declare module "svelte/elements" {
  interface HTMLAttributes<T extends EventTarget> {
    "phx-click"?: string;
    "phx-update"?: string;
  }
}
