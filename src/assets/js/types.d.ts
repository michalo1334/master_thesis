declare module "phoenix-colocated/network_defense" {
  export const hooks: import("phoenix_live_view").HooksOptions;
}

declare module "virtual:live-svelte-components" {
  const components: import("live_svelte").ComponentModuleInput;
  export default components;
}
