# Evaluation Report "The operation could not be completed." — Post-mortem

## Symptom

Starting or recovering an evaluation report in the dashboard showed
"The operation could not be completed." even when the run was completed and
the report data existed in the database.

## Root Causes

1. **Wrong success-key check in the report event handler.**
   `NetworkDefense.Evaluation.EvaluationReport.generate/2` returns the report
   map directly (keyed by `run_id`, `status`, ...). But
   `DashboardLive.handle_info({:evaluation_report_result, ...})` tested
   `result[:report]`, which is never set. Every evaluation report fetch fell
   into the error branch and the non-nil result was mapped to `internal_error`
   → "The operation could not be completed." The LiveView test encoded the
   same wrong wrapper shape (`%{report: report}`), so it never caught this.

2. **Terminal runs were never re-announced.**
   `Evaluation.start/1` reuses the latest completed run for the same manifest
   (`start_or_reuse`). The enqueued Oban job called `Evaluation.run/1`, which
   short-circuits for `completed`/`failed` runs without broadcasting
   `evaluation_completed`. A freshly opened report stayed "pending" forever.

## Fixes

- `lib/network_defense_web/live/web/dashboard/dashboard_live.ex`:
  - the report-fetch task returns `{:ok, report} | {:error, :not_found |
    :internal_error}`; `handle_info` pattern-matches the tuple instead of
    sniffing payload shape;
  - a missing run/graph maps to `not_found`; a raised generator (rescued in
    the task) maps to `internal_error`.
- `lib/network_defense/evaluation.ex`:
  - `Evaluation.run/1` re-broadcasts `evaluation_completed` /
    `evaluation_failed` when the requested run is already terminal
    (`reannounce_terminal/1`).
- `assets/svelte/dashboard/DashboardModel.svelte.ts`:
  - `onEvaluationCompleted` / `onEvaluationFailed` share one private helper;
    it skips re-fetching when the report is already `loaded`.
- `assets/svelte/dashboard/analysis-report/AnalysisReportDocument.svelte.ts`:
  - `recover/1` issues the fetch directly (`load/3` already sets the loading
    state).

## Verification

- `mix precommit` passes: format, typecheck, credo, dialyzer, sobelow,
  383 tests (3 new/updated in `dashboard_live_test.exs`, 2 new in
  `DashboardModel.svelte.test.ts`).
- GUI (playwright-cli): fresh start of `hkjkjk` and `repro-1` renders the full
  report (Summary, Plans, Aggregate results); page-reload recovery of the
  persisted reports also renders. No "could not be completed." in the DOM.
