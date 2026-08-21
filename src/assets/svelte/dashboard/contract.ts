import type {
  Node,
  Edge,
  GraphContract,
  OptimizationParams as GeneratedOptimizationParams,
  SimulationParams as GeneratedSimulationParams,
  FetchSimulationReportReply,
  EvaluationReport,
} from "../contracts.generated";

export type {
  HostData,
  ServiceData,
  VulnerabilityData,
  RunsData,
  SegmentReachabilityData,
  HasVulnerabilityData,
  CredentialData,
  NetworkSegmentData,
  StoresCredentialData,
  AuthenticatesToData,
  CredentialNode,
  MissionCapabilityNode,
  NetworkSegmentNode,
  SegmentReachabilityEdge,
  HasVulnerabilityEdge,
  StoresCredentialEdge,
  AuthenticatesToEdge,
  ContainsEdge,
  NodeViewData,
  Node,
  Edge,
  OpenGraphPayload,
  OpenGraphReply,
  SaveGraphPayload,
  SaveGraphReply,
  RunSimulationRequest,
  RunSimulationPayload,
  RunSimulationReply,
  OptimizationAction,
  OptimizationCompletedEvent,
  OptimizationReport,
  ExecutionProgressEvent,
  OptimizationFailedEvent,
  OptimizationReportErrorEvent,
  OptimizationRunSummary,
  RunOptimizationPayload,
  RunOptimizationReply,
  FetchSimulationReportPayload,
  FetchSimulationReportReply,
  SimulationReportReadyEvent,
  SimulationCompletedEvent,
  SimulationFailedEvent,
  ExperimentSummary,
  FetchExperimentsPayload,
  FetchExperimentsReply,
  FetchOptimizationReportPayload,
  FetchOptimizationReportReply,
  OptimizationReportReadyEvent,
  FetchOptimizationRunsPayload,
  FetchOptimizationRunsReply,
  CreateNodeDraftPayload,
  CreateNodeDraftReply,
  CreateConnectionDraftPayload,
  CreateConnectionDraftReply,
  GraphConnectivityReply,
  GraphConnectivityRule,
  CompareGraphsPayload,
  CompareGraphsReply,
  GraphDiffResult,
  GraphDiffCounts,
  GraphDiffStatusEntry,
  SetGraphRevisionFavoritePayload,
  SetGraphRevisionFavoriteReply,
  FolderSummary,
  CreateFolderPayload,
  CreateFolderReply,
  DeleteFolderPayload,
  DeleteFolderReply,
  MoveGraphToFolderPayload,
  MoveGraphToFolderReply,
  FetchGraphProjectionPayload,
  FetchGraphProjectionReply,
  GraphProjectionOperationalFlow,
  FetchDocumentCatalogPayload,
  FetchDocumentCatalogReply,
  DocumentCatalogItem,
  SimulationReportErrorEvent,
  DashboardError,
  ErrorCode,
  GetManifestPayload,
  GetManifestReply,
  ListManifestsPayload,
  ListManifestsReply,
  ManifestError,
  ManifestSummary,
  SaveManifestPayload,
  SaveManifestReply,
  StartEvaluationPayload,
  StartEvaluationReply,
  FetchEvaluationReportPayload,
  FetchEvaluationReportReply,
  EvaluationReport,
  EvaluationCompletedEvent,
  EvaluationFailedEvent,
  EvaluationReportReadyEvent,
  EvaluationReportErrorEvent,
} from "../contracts.generated";

export type LoadedGraph = GraphContract;

export type GraphSummary = import("../contracts.generated").GraphSummary;

export type SimulationParams = GeneratedSimulationParams;

export type OptimizationStrategy = GeneratedOptimizationParams["strategy"];

export type OptimizationParams = GeneratedOptimizationParams;

export type Selectable = Node | Edge;

export type SimulationReportData = FetchSimulationReportReply;

export type EvaluationReportData = EvaluationReport;

export type OptimizationParamsChange = Omit<
  Partial<OptimizationParams>,
  "simulation_params"
> & {
  simulation_params?: Partial<SimulationParams>;
};
