import { alignSelection } from "./definitions/align-selection";
import { clearSelection } from "./definitions/clear-selection";
import { connectTool } from "./definitions/connect-tool";
import { duplicateSelection } from "./definitions/duplicate-selection";
import { lockSelection } from "./definitions/lock-selection";
import { optimizeDefense } from "./definitions/optimize-defense";
import { removeSelection } from "./definitions/remove-selection";
import { runSimulation } from "./definitions/run-simulation";
import { selectTool } from "./definitions/select-tool";
import { selectTopologyObject } from "./definitions/select-topology-object";
import { setTopologyLayout } from "./definitions/set-topology-layout";
import { showGraph } from "./definitions/show-graph";
import { showList } from "./definitions/show-list";
import { toggleInspector } from "./definitions/toggle-inspector";
import { toggleZoneBoundaries } from "./definitions/toggle-zone-boundaries";
import type {
  CommandContext,
  CommandDefinition,
  CommandId,
  CommandArguments,
} from "./types";

export type {
  ActiveDocument,
  CommandArguments,
  CommandContext,
  CommandDefinition,
  CommandId,
  CommandSource,
  DashboardUiState,
  SelectedTopologyObject,
  TopologyLayout,
  TopologyTool,
} from "./types";

export const commandDefinitions: {
  [Id in CommandId]: CommandDefinition<Id>;
} = {
  "select-tool": selectTool,
  "connect-tool": connectTool,
  "set-topology-layout": setTopologyLayout,
  "toggle-zone-boundaries": toggleZoneBoundaries,
  "toggle-inspector": toggleInspector,
  "show-graph": showGraph,
  "show-list": showList,
  "select-topology-object": selectTopologyObject,
  "clear-selection": clearSelection,
  "duplicate-selection": duplicateSelection,
  "remove-selection": removeSelection,
  "lock-selection": lockSelection,
  "align-selection": alignSelection,
  "run-simulation": runSimulation,
  "optimize-defense": optimizeDefense,
};

export function commandAvailable(id: CommandId, context: CommandContext) {
  return commandDefinitions[id].isAvailable(context);
}

export function executeCommand<Id extends CommandId>(
  id: Id,
  context: CommandContext,
  args: CommandArguments[Id] = undefined as CommandArguments[Id],
) {
  const command = commandDefinitions[id] as CommandDefinition<Id>;

  if (!command.isAvailable(context)) return false;

  command.execute(context, args);
  return true;
}
