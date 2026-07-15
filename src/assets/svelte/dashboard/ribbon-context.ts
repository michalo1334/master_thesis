import { createContext } from "svelte";

interface RibbonTab {
  title: () => string;
  value: string;
}

interface RibbonContext {
  registerTab: (tab: RibbonTab) => () => void;
}

export const [getRibbonContext, setRibbonContext] = createContext<RibbonContext>();
