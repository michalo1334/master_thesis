import Root from "./Ribbon.svelte";
import Section from "./RibbonSection.svelte";
import Tab from "./RibbonTab.svelte";

const Ribbon = Object.assign(Root, { Tab, Section });

export default Ribbon;
