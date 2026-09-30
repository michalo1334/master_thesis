import type {
  EvaluationAnalysis,
  StartStudyAnalysisPayload,
} from "../../contracts.generated/dashboard/evaluation";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/svelte";
import type { DashboardApi } from "../dashboard-api";
import Study from "./Study.svelte";
import { StudyDocument } from "./StudyDocument.svelte";
import type { StudyLockedInputs } from "./study-types";

function locked(): StudyLockedInputs {
  return {
    title: "Study one",
    study_id: "study-one",
    specification_id: "spec-1",
    specification_version: 2,
    tiers: [
      {
        tier: "small",
        run_id: "run-1",
        manifest_title: "Baseline manifest",
        graph_title: "Gateway",
        plan_count: 5,
        trial_count: 50,
      },
    ],
  };
}

function analysis(mode: "study-pilot" | "study-analyze"): EvaluationAnalysis {
  return {
    capability_results: [],
    feasibility_summary: [],
    metadata: {
      command_mode: mode,
      family_scope: "study",
      family_size: 1,
      ...(mode === "study-pilot"
        ? {
            recommended_plan_selection_seed_count: 4,
            recommended_attacks_per_plan: 10,
            insufficient_pilot: false,
          }
        : {}),
    },
    pilot_results: [],
    primary_results: [],
    secondary_results: [],
  };
}

function withPilot(eligible: boolean): StudyDocument {
  const document = new StudyDocument("doc-1", locked());
  document.markStarted("pilot");
  document.attemptId = "attempt-1";
  document.onReady({
    document_id: "doc-1",
    mode: "pilot",
    attempt_id: "attempt-1",
    archive: btoa("pilot-archive"),
    pilot_eligible: eligible,
    analysis: analysis("study-pilot"),
  });
  return document;
}

function studyApi(): DashboardApi {
  return {
    listStudyTierRuns: vi.fn().mockResolvedValue({
      runs: [
        {
          id: "final-run-1",
          manifest_id: "final-manifest",
          manifest_title: "Final manifest",
          graph_title: "Gateway",
          completed_at: "2026-01-02T03:04:05Z",
          plan_count: 5,
          trial_count: 50,
        },
      ],
      required_inputs: "final inputs",
    }),
    preflightStudy: vi.fn().mockResolvedValue({ status: "ok", errors: [] }),
    startStudyAnalysis: vi
      .fn()
      .mockImplementation(
        async (payload: { document_id: string; mode: "pilot" | "final" }) => ({
          status: "accepted",
          document_id: payload.document_id,
          mode: payload.mode,
          attempt_id: "attempt-2",
          errors: [],
        }),
      ),
    closeStudyDocument: vi.fn().mockResolvedValue({ status: "closed" }),
  } as unknown as DashboardApi;
}

function startPayloads(api: DashboardApi): StartStudyAnalysisPayload[] {
  return vi
    .mocked(api.startStudyAnalysis)
    .mock.calls.map(([payload]) => payload);
}

afterEach(cleanup);

describe("Study", () => {
  it("shows the locked setup once in the document header", () => {
    render(Study, {
      props: { document: new StudyDocument("doc-1", locked()) },
    });

    expect(
      screen.getByRole("heading", { name: "Study one" }),
    ).toBeInTheDocument();
    expect(screen.getByText("study-one")).toBeInTheDocument();
    expect(screen.getByText("2")).toBeInTheDocument();
    expect(
      screen.getByRole("rowheader", { name: "small" }),
    ).toBeInTheDocument();
    expect(screen.getByText("Baseline manifest")).toBeInTheDocument();
    expect(screen.getByText("5 / 50")).toBeInTheDocument();
  });

  it("shows the named phases with the active one marked", () => {
    const study = new StudyDocument("doc-1", locked());
    study.markStarted("pilot");
    study.applyPhase("validating_result");

    render(Study, { props: { document: study } });

    expect(screen.getByText("Building bundle")).toBeInTheDocument();
    expect(screen.getByText("Validating result")).toBeInTheDocument();
    expect(screen.getByText("Validating result").closest("li")).toHaveAttribute(
      "aria-current",
      "step",
    );
    expect(screen.getByText("Pilot analysis running")).toBeInTheDocument();
  });

  it("shows a failure with an in-place retry and no Cancel button", async () => {
    const study = new StudyDocument("doc-1", locked());
    const api = studyApi();
    study.markStarted("pilot");
    study.markError("The analysis service is unreachable.");

    render(Study, { props: { document: study, api } });

    expect(screen.getByRole("alert")).toHaveTextContent(
      "The analysis service is unreachable.",
    );
    expect(
      screen.queryByRole("button", { name: /cancel/i }),
    ).not.toBeInTheDocument();

    await fireEvent.click(
      screen.getByRole("button", { name: "Retry pilot analysis" }),
    );

    await waitFor(() =>
      expect(startPayloads(api)[0]).toEqual({
        document_id: "doc-1",
        mode: "pilot",
        specification_id: "spec-1",
        tier_runs: [{ tier: "small", run_id: "run-1" }],
      }),
    );
  });

  it("offers final after an eligible pilot and renders the shared report", async () => {
    const study = withPilot(true);
    study.finalMapping.selections = { small: "final-run-1" };
    study.finalMapping.preflightStatus = "ok";
    const api = studyApi();

    render(Study, { props: { document: study, api } });

    expect(screen.getByRole("tab", { name: "Pilot" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Final" })).toBeInTheDocument();
    expect(
      screen.getByRole("heading", { name: "Pilot planning results" }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Download pilot result ZIP" }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: /cancel/i }),
    ).not.toBeInTheDocument();

    await fireEvent.click(
      await screen.findByRole("button", { name: "Run final" }),
    );

    await waitFor(() =>
      expect(startPayloads(api)[0]).toEqual({
        document_id: "doc-1",
        mode: "final",
        specification_id: "spec-1",
        tier_runs: [{ tier: "small", run_id: "final-run-1" }],
      }),
    );
  });

  it("shows a row message and summary for a partial final mapping without generic mismatch text", async () => {
    const inputs = locked();
    inputs.tiers = [
      ...inputs.tiers,
      {
        tier: "large",
        run_id: "run-2",
        manifest_title: "Large pilot manifest",
        graph_title: "Gateway",
        plan_count: 5,
        trial_count: 50,
      },
    ];
    const study = new StudyDocument("doc-1", inputs);
    study.markStarted("pilot");
    study.attemptId = "attempt-1";
    study.onReady({
      document_id: "doc-1",
      mode: "pilot",
      attempt_id: "attempt-1",
      archive: btoa("pilot-archive"),
      pilot_eligible: true,
      analysis: analysis("study-pilot"),
    });
    const api = studyApi();
    vi.mocked(api.listStudyTierRuns).mockImplementation(async (payload) => ({
      runs: [
        {
          id: `final-${payload.tier}`,
          manifest_id: `final-manifest-${payload.tier}`,
          manifest_title: `${payload.tier} final manifest`,
          graph_title: "Gateway",
          completed_at: "2026-01-02T03:04:05Z",
          plan_count: 5,
          trial_count: 50,
        },
      ],
      required_inputs: "final inputs",
    }));
    vi.mocked(api.preflightStudy).mockImplementation(async (payload) => ({
      status: "rejected",
      errors:
        payload.tier_runs.length === 0
          ? [{ code: "no_tiers" }]
          : [
              { code: "tier_declaration_mismatch" },
              { code: "run_incompatible" },
            ],
    }));

    render(Study, { props: { document: study, api } });
    await waitFor(() => expect(study.finalMapping.isLoading).toBe(false));
    study.finalMapping.selectRun("small", "final-small");

    await waitFor(() =>
      expect(
        screen.getByText(
          "A selected evaluation run does not match the required study inputs.",
        ),
      ).toBeInTheDocument(),
    );
    expect(
      screen.getByText("Select one completed run for every declared tier."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("Select one completed run for this tier."),
    ).toBeInTheDocument();
    expect(
      screen.queryByText("The mapping does not match the declared tiers."),
    ).not.toBeInTheDocument();
  });

  it("keeps final disabled after an insufficient pilot and warns about the rerun", () => {
    render(Study, { props: { document: withPilot(false) } });

    expect(
      screen.queryByRole("button", { name: "Run final" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Rerun pilot" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "reproduce the same stop condition",
    );
    expect(
      screen.queryByRole("button", { name: /cancel/i }),
    ).not.toBeInTheDocument();
  });

  it("offers only the retry after a final failure", () => {
    const study = withPilot(true);
    study.markStarted("final");
    study.markError("The analysis service is unreachable.");

    render(Study, { props: { document: study } });

    expect(
      screen.queryByRole("button", { name: "Run final" }),
    ).not.toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Retry final analysis" }),
    ).toBeInTheDocument();
  });
});
