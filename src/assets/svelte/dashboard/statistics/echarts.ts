import {
  BarChart,
  BoxplotChart,
  HeatmapChart,
  LineChart,
  PieChart,
  ScatterChart,
} from "echarts/charts";
import {
  AriaComponent,
  GridComponent,
  LegendComponent,
  TooltipComponent,
  VisualMapComponent,
} from "echarts/components";
import { init, use } from "echarts/core";
import { CanvasRenderer } from "echarts/renderers";

use([
  AriaComponent,
  BarChart,
  BoxplotChart,
  CanvasRenderer,
  GridComponent,
  HeatmapChart,
  LegendComponent,
  LineChart,
  PieChart,
  ScatterChart,
  TooltipComponent,
  VisualMapComponent,
]);

export { init };
