import type {
  StartStudyAnalysisPayload,
  StudyAnalysisProgressEvent,
  StudyAnalysisReadyEvent,
  StudyRunError,
  StudySpecificationSummary,
  StudyTierRunSummary,
  StudyTierSelection,
} from "../../contracts.generated/dashboard/evaluation";

/** Browser-only dialog state. */
export type StudyTab = "json" | "preview" | "run";

export type StudyMode = StartStudyAnalysisPayload["mode"];
export type StudyPhase = StudyAnalysisProgressEvent["phase"];

export const STUDY_PHASE_LABELS = {
  building_bundle: "Building bundle",
  submitting_analysis: "Submitting analysis",
  waiting_for_service: "Waiting for service",
  validating_result: "Validating result",
  complete: "Complete",
} satisfies Record<StudyPhase, string>;

/** Ordered from the exhaustive generated-phase label map. */
export const STUDY_PHASES = Object.keys(STUDY_PHASE_LABELS) as StudyPhase[];

/**
 * One declared tier locked to one completed evaluation run.
 *
 * The run summary fields are display metadata only, so a mapping may carry a
 * bare selection when the summary is not loaded yet.
 */
export type StudyTierMapping = StudyTierSelection &
  Partial<
    Pick<
      StudyTierRunSummary,
      | "manifest_title"
      | "graph_title"
      | "completed_at"
      | "plan_count"
      | "trial_count"
    >
  >;

/** Immutable inputs that a live study document locks when Pilot starts. */
export type StudyLockedInputs = Pick<
  StudySpecificationSummary,
  "title" | "study_id" | "specification_version"
> & {
  /** This document only exists for a saved specification. */
  specification_id: NonNullable<StartStudyAnalysisPayload["specification_id"]>;
  tiers: StudyTierMapping[];
};

/**
 * One delivered Pilot or Final result plus browser-only download state.
 *
 * `archive` holds the exact result ZIP bytes as base64, delivered once by the
 * server. `downloadRequested` records that a download was requested; it never
 * claims the browser finished the download.
 */
export type StudyResult = Pick<
  StudyAnalysisReadyEvent,
  "analysis" | "archive" | "pilot_eligible"
> & {
  downloadRequested: boolean;
};

/**
 * Validates a wire phase before it reaches the document state.
 *
 * Event payloads cross an `unknown` boundary, so an unexpected phase must not
 * reach the phase display.
 */
export function isStudyPhase(value: string): value is StudyPhase {
  return (STUDY_PHASES as readonly string[]).includes(value);
}

/**
 * Locks the exact tier-run mapping for one Pilot start.
 */
export function lockedTierSelections(
  locked: StudyLockedInputs,
): StudyTierSelection[] {
  return locked.tiers.map(({ tier, run_id }) => ({ tier, run_id }));
}

/** Projects one tier-to-run selection map to the wire tier-selection list. */
export function tierSelectionsFrom(
  tiers: readonly string[],
  selections: Readonly<Record<string, string>>,
): StudyTierSelection[] {
  return tiers.flatMap((tier) => {
    const runId = selections[tier];
    return runId ? [{ tier, run_id: runId }] : [];
  });
}

export const RUN_ERROR_MESSAGES: Record<StudyRunError["code"], string> = {
  invalid_request: "The request is not valid.",
  invalid_specification: "The saved specification is not valid.",
  specification_not_found: "The saved specification no longer exists.",
  invalid_tier_selection: "The tier selection is not valid.",
  unsafe_tier_label: "A declared tier label is not safe.",
  duplicate_tier_label: "A tier label is declared more than once.",
  duplicate_run_id: "One evaluation run is mapped to more than one tier.",
  run_overlap:
    "An evaluation run is mapped to both the pilot and the final analysis.",
  invalid_run_id: "A selected run identifier is not valid.",
  no_tiers: "Select one completed run for every declared tier.",
  run_not_found: "A selected evaluation run no longer exists.",
  run_incomplete: "A selected evaluation run is not complete.",
  run_not_exportable: "A selected evaluation run cannot be exported.",
  run_warmup: "A warm-up evaluation run cannot enter a study.",
  run_incompatible:
    "A selected evaluation run does not match the required study inputs.",
  tier_declaration_mismatch: "The mapping does not match the declared tiers.",
  tier_archive_too_large: "A selected run archive is too large.",
  input_too_large: "The study bundle exceeds the input limit.",
  output_too_large: "The study bundle exceeds the output limit.",
  result_too_large: "The analysis result exceeds the download limit.",
  invalid_mode: "The analysis mode is not valid.",
  final_not_available: "Final analysis is not available for this pilot.",
  already_running: "This study document already runs an analysis.",
  document_locked: "This study document is locked to different inputs.",
  document_not_found: "The study document no longer exists.",
  not_configured: "The analysis service is not configured.",
  transport: "The analysis service is unreachable.",
  http_status: "The analysis service returned an error.",
  content_type: "The analysis service returned an unexpected format.",
  response_too_large: "The analysis response is too large.",
  invalid_body: "The analysis response body is not valid.",
  invalid_result: "The analysis result is not valid.",
  cancelled: "The analysis was cancelled.",
  internal_error: "The analysis failed unexpectedly.",
};

const UNKNOWN_RUN_ERROR = "The study request failed.";
const MISSING_TIER_MAPPING_ERROR_CODES = new Set<StudyRunError["code"]>([
  "no_tiers",
  "tier_declaration_mismatch",
]);

export function formatStudyRunError(error: StudyRunError): string {
  return RUN_ERROR_MESSAGES[error.code] ?? UNKNOWN_RUN_ERROR;
}

/**
 * Keeps browser-known missing selections specific while retaining every other
 * server preflight error. The server still decides whether preflight passes.
 */
export function visibleStudyRunErrors(
  errors: readonly StudyRunError[],
  hasMissingSelections: boolean,
): StudyRunError[] {
  if (!hasMissingSelections) return [...errors];
  return errors.filter(
    (error) => !MISSING_TIER_MAPPING_ERROR_CODES.has(error.code),
  );
}

const DEFAULT_TIERS = ["small"];

export function declaredTierLabels(content: unknown): string[] {
  const record = asRecord(content);
  const tiers = record ? record.tiers : undefined;
  if (!Array.isArray(tiers)) return [];
  return tiers.flatMap((entry) => {
    if (typeof entry === "string") return [entry];
    const label = asRecord(entry)?.label;
    return typeof label === "string" ? [label] : [];
  });
}

export function createDefaultStudySpecification(studyId: string): string {
  return JSON.stringify(
    {
      study_id: studyId,
      specification_version: 1,
      tiers: DEFAULT_TIERS,
      expected_family: {
        strategies: ["simulation_informed"],
        baseline: "cvss",
        budgets: [1],
        outcome: "mission_impact",
      },
      pilot: {
        ci_half_width: 0.05,
        plan_count_candidates: [5, 10],
        attacks_per_plan_candidates: [10, 20],
      },
      multiplicity_correction: "holm",
      pilot_seed_schedule: { selection: [101], evaluation: [201] },
      final_seed_schedule: { selection: [102], evaluation: [202] },
    },
    null,
    2,
  );
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}
