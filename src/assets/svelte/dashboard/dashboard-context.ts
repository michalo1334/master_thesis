import { createContext } from "svelte";
import { DashboardController } from "./DashboardController.svelte";

export const [getDashboardContext, setDashboardContext] =
  createContext<DashboardController>();
