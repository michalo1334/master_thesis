# Goal 03 — Pilot workflow

## Outcome and clock

- Shared budget start UTC: **2026-10-31T14:16:38Z**.
- Shared deadline UTC: **2026-10-31T17:16:38Z**, exactly 10,800 seconds after budget start.
- Goal 03 implementation started after the Goal 02 audit, about **14:52Z**. The user's combined run has one three-hour allowance. Resume did not reset it.
- Reserved verification/report window: **17:01:38Z**. Implementation, verification and reporting finished early.
- Final completion audit UTC: **2026-10-31T16:00:28Z**. Shared elapsed time: **1 hour, 43 minutes, 50 seconds**.
- Status: **verified complete for Goal 03**. The real service-backed Pilot, separate-VM cancellation check, final link-fence review and serialized full gate pass.

## Assignments and ownership

| Helper | Model and bounded assignment | Outcome |
|---|---|---|
| `pilot-dag-codecs` | worker, `deepseek/deepseek-flash`; Pilot analysis codecs, DAG/actions and pure cases | Delivered; follow-up extracted duplicated action-boundary mechanics and checked Credo/format |
| `pilot-wait-monitor` | worker, `deepseek/deepseek-flash`; wait-only monitor, one application child and monitor cases | Delivered after a classification fix; 12 real-DB tests passed |
| `pilot-runtime-scout` | read-only `deepseek/deepseek-flash`; local services and runtime source | Identified absent broker and normal application/Gust configuration |
| `pilot-review` | reviewer, `deepseek/deepseek-flash`; independent source, tests and requirement audit | Pilot implementation, review fixes and final link/cancellation fence approved |

The owner implemented canonical provisioning/completion, caller-owned progression, Pilot assessment/selection, persistence reads/cost samples, facade/report integration and real executions. Helpers received the shared deadline and instructions to address Credo and formatter findings. No helper delegated recursively.

## Prompt-to-artifact audit

The concrete deliverable is a supported `Study.start` plus caller-owned `continue/1,2` path that accepts real Pilot Collection through existing Persistence transactions, runs native Pilot Analysis, persists its compact outcome and exposes the complete report at `awaiting_final`.

Paths below are relative to `src/` unless stated otherwise.

| Explicit requirement | Artifact and direct evidence |
|---|---|
| Goals 01–02 pass first; read governing contracts | Goal 02 scoped audit and final precommit passed before Goal 03 workers/implementation started. Goal README, sketches, refactor brief, test plan, phase contracts and current transaction owners informed the work. |
| Preserve the shared three-hour deadline and worker rules | Clock and assignments above; no timer flag, new goal or deadline extension. |
| `Study.start`, `continue/1`, `continue/2` | `study.ex`, `study/workflow.ex`; indefinite continuation reaches the approval boundary; finite continuation returns current Status. Real development execution and FLOW/BIND integration cases exercise the facade. |
| Real Collection reconciliation and existing acceptance owners | Workflow proves the canonical collection result, then calls `Persistence.Executions.accept_pilot_collection/1`. Collection still prepares its phase-owned snapshot. Acceptance creates the analysis successor under the existing transaction. |
| Canonical create-link-dispatch and authoritative Gust locking | Workflow allocates the PhaseRun UUID, creates an undispatched Gust run, links it and dispatches the canonical winner. Gust status is checked under `FOR UPDATE`. BIND-01 tests repeated and concurrent continuations and checks one linked run per phase. |
| Cancellation cannot win before a new link and still permit provisioning | `Persistence.link_phase_run/4` locks the execution before the phase. New links require that execution's active phase; existing links remain idempotent. A forced cancellation-before-link regression failed before this fix and now passes. Workflow removes only its own still-created rejected run. |
| Complete canonical proof and snapshot identity | Completion requires the canonical link, exact phase/run/snapshot input, succeeded run, one succeeded phase-specific terminal task and typed output. Analysis validates complete candidate/comparison membership and selected outcome. Wrong snapshot and incomplete terminal output tests reject acceptance without advancing. |
| Pilot DAG, actions and strict codecs | `priv/gust/dags/evaluation2_study_pilot_analysis.exs`; `workflow/pilot_analysis/actions/*`; `pilot/analysis_contract.ex`. Actions bind their acting run and snapshot owner. Foreign run, phase and execution snapshot cases fail. |
| Native assessments at the shared confidence level | `pilot/analysis.ex` binds candidate/comparison positions and the declared comparison planning seed, supplies frozen bounds, and calls `Compute.pilot_precision/5` with `definition.analysis`. Targets and returned spans use outcome units. |
| Complete fan-in, reference costs and selection | `Analysis.summarize/3` rejects missing/duplicate coordinates and inconsistent pass decisions. Cost samples count physical replica-0 items once, exclude warm-up, require completed effects and positive trial counts. The fixed heuristic uses tier count, maximum unique group count per tier, median plan/trial cost, and candidate counts. Tie-breaks are runtime, more plans, fewer attacks, then declared position. PILOT-01/02 cases check these quantities independently. |
| An insufficient Pilot is a valid report | Real Pilot returns insufficient, with all six widths and failed target decisions visible. Policy tests cover recommendation, insufficiency and ties. |
| Persist outcome and expose complete report | Existing acceptance stores only `PilotOutcome`; Gust's terminal output stores complete candidate summaries. `Study.pilot_result/1` proves that terminal output and joins immutable identities through Views. A later application VM reads the same real report successfully. |
| One progression loop; wait-only monitor | Workflow owns all progression. `workflow/run_monitor.ex` only observes Gust and durable execution state. Application supervises it. It owns no provisioning, acceptance or cancellation. |
| Timeout without cancellation | FLOW-03 and monitor cases keep execution/run active on timeout. Invalid timeout returns `:validation_failed`. Timeout is an API wait bound, not a scientific stopping rule. |
| Cross-VM cancellation and late completion | Monitor polls durable state rather than relying on local notifications. Actual separate VMs confirm a blocked continuation returns cancelled. A real late collection receipt after cancellation fails lifecycle acceptance and creates no analysis successor. |
| Best-effort stopping uses Gust's existing states | After durable cancellation, pending created/enqueued runs become `:failed` under the authoritative Gust row lock. Active runs use Gust's stop gateway. No Gust cancelled state was added. Repeated cancellation leaves no queued development run. |
| Independent future Final inputs | Pilot evidence remains Pilot-owned. Existing phase-separated seed allocation stays intact, and continuation grants no approval. Invalid recommended approval leaves an insufficient outcome at the gate; explicit override freezes the declared counts. Actual Final collection remains the next milestone. |
| No second coordinator, Pilot.Collection facade, tier cursor, generic workflow framework or report cycle | Source audit and review confirm one caller-owned loop, a wait-only observer and small shared action mechanics. Views only constructs values; report reads do not orchestrate progression. |
| Compile, BIND/FLOW/PILOT/RESULT and scoped CMD evidence | Focused tests, source review, normal-application development run and final serialized precommit below. Full Final command/study cases remain later milestones. |
| Preserve work/data/shared APIs; no forbidden operations | No reset, commit, Terraform apply, credential-file change or retirement. Original five development revision identities remain. Temporary broker and disposable helpers were removed. |

## Real development Pilot

The normal development application used its retained in-process optimizer, **RabbitMQExecutor**, RabbitMQ worker and Gust execution runtime. No local/test executor replaced simulation.

- Frozen revision: `evaluation2-pilot-20261031`, revision **1**.
- Execution ID: **`d32cfaef-e4fe-4713-9c07-2a82ed32c19d`**.
- State: **`awaiting_final`**.
- Outcome: **`insufficient`**.
- Candidate `tiny`: one plan per side, two attacks; two outer subsets; confidence 0.95; guard 0.9; target half-width 0.2 outcome units.
- Three seeded graph tiers; two alternatives versus the shared CVSS reference per tier.
- **9 unique groups / 9 physical items / 6 comparisons**. Every half-width is 8.0, so every comparison visibly misses the target.
- Pilot Collection Gust run **1**, Pilot Analysis Gust run **2**. The report artifact records phase, PhaseRun, snapshot, optimization and experiment identities.
- No Final approval or Final execution occurred for this execution.

Durable artifact, inspected again during audit:

`local-results/evaluation2-pilot-d32cfaef-e4fe-4713-9c07-2a82ed32c19d.json`

A later normal application VM, using Gust's observational `console` role, read the report at **2026-10-31T15:34:40Z**. It returned the same insufficient outcome, one candidate and six comparisons. The stored evidence and report survive the original caller VM.

### Separate-VM cancellation

- Execution: **`51a4f542-e804-4b0e-a6ac-ec11c3a726a3`**.
- First VM started the normal application, queued a Pilot and entered a real monitor wait. A state barrier checked that the wait existed before cancellation.
- A FIFO passed only the execution ID to the second VM. That VM started the normal application and called `Study.cancel/1`.
- The first VM received **cancelled** through the durable-state poll, without a local cancellation notification.
- Both VMs used Gust's console role to keep the queued work controlled. Separate metrics ports avoided a runtime conflict.
- Repeated cancellation after the pending-run fix fenced its Gust run as failed. Final development Gust counts are **2 succeeded / 1 failed**, with no queued or active run.

Artifact:

`local-results/evaluation2-cancellation-51a4f542-e804-4b0e-a6ac-ec11c3a726a3.json`

## Commands and safety evidence

Automated checks used the existing local environment plus the mounted password file. Both Repo configurations were checked before DB use: **localhost:5433 / network_defense_test**, postgres, SQL Sandbox. Default localhost:5432 is a different instance and was not used by Goal 03 helpers or owner.

Manual checks separately verified both development Repos as **localhost:5433 / network_defense_dev**. Before starting execution-capable Gust, a direct read found **zero existing Gust runs**, so startup could not claim unrelated work.

The real run needed the two existing additive Goal 01 migrations. After target verification, the owner ran:

```sh
MIX_ENV=dev mix ecto.migrate -r NetworkDefense.Repo -r Gust.Repo
```

Only migrations `20261031131000` and `20261031134500` were pending. Both applied successfully; Gust was already current. No development reset or reseed occurred.

The broker was absent. The owner pulled `rabbitmq:4.1-management` (digest `sha256:bf215c927c885b6d28bc52e02b0f2e1c033f2b439ec946c643834be93312ec4d`) and started an owned temporary container, `evaluation2-pilot-rabbitmq`, bound only to localhost:5672. Its configuration used the existing mounted secret. Ping and authenticated application connection passed. The owner stopped/removed that container and its owned volume/configuration after verification. Terraform and existing containers were untouched; the downloaded image remains only as a cache.

Development original revision identities, before and after all checks, use the same ordered JSON digest:

`7f2c3a5857507636792bd63223dfe46d40d57a73f1c694833fddb7b0b10f8a1c`

All **five** original rows remain. `/tmp/evaluation2-goal03-dev-final-safety.log` records that check and the terminal Gust counts. Real-run output revisions and study records remain as intended evidence.

One offline connection-start diagnostic included connection fields. The owner redacted mounted secret values from owned logs. No credential file changed. Disposable real-run/cross-VM scripts, environment helper, FIFO and broker configuration were removed; JSON evidence remains.

| Exact check | Result and evidence |
|---|---|
| `mix compile --warnings-as-errors` | Passed; also part of precommit |
| `MIX_ENV=test mix test test/network_defense/evaluation2` | Latest **229 passed**, including the forced link-cancellation race; `/tmp/evaluation2-pilot-link-cancel-green.log` |
| Focused Pilot policy/workflow, monitor and codec cases | Review checked prior 36-case slice; owner added explicit late-valid receipt, failed canonical run and cancellation-before-link cases afterward. Current folder check covers them. |
| `mix credo --strict --format flycheck` | Exit 0 after final link fix; `/tmp/evaluation2-link-cancel-credo.log` |
| `mix format --check-formatted`; `git diff --check` | Passed in gates/current worktree |
| `MIX_ENV=dev mix run /tmp/evaluation2-goal03-real-pilot.exs` | Exit 0, real Pilot evidence above; `/tmp/evaluation2-goal03-real-pilot.log`. Script was disposable and is removed. |
| Two `MIX_ENV=dev mix run --no-start` callers that each start the normal application | Both exit 0; `/tmp/evaluation2-goal03-cross-vm-{wait,cancel}.log` |
| Later normal application report/cancellation read | Exit 0; `/tmp/evaluation2-pilot-persisted-report.log` |
| `MIX_ENV=test timeout 240 mix precommit` | **867 passed, 2 excluded**, exit 0 after the final link fix and all reviews; `/tmp/evaluation2-goals02-03-final-gate.log`. Compile, generated contracts, Elixir/frontend formatting and type checks, assets, strict Credo, Dialyzer, Sobelow and dependencies also pass. |

The Credo and formatter inputs now include the new `scripts/` directory, so the statistical runner participates in the normal lint/format gate.

## Findings and fixes

1. Worker monitor classification initially unwrapped a tagged result incorrectly. Worker corrected it before handoff; real-DB monitor tests pass.
2. Exact duplicated logging/run-ID checks were extracted into `workflow/action_boundary.ex`. This utility has no state or coordination role. Strict Credo then passed.
3. A cancellation race between the first context read and phase provisioning returned `phase_not_active`. Workflow now reloads a changed state. A controlled storage-read barrier forces that race; real acceptance and effects remain intact.
4. Final audit found the stronger cancellation-before-link race. The old code linked and dispatched a new analysis run after cancellation. The regression failed first. Execution-first locking and active-phase authorization now fence new links; rejected created runs are cleaned up. Existing canonical links keep their idempotent read behavior.
5. Gust's stop gateway returns success without changing an enqueued run when no runner exists. The actual cross-VM check exposed that queued leftover. Pending-run fencing under the Gust row lock fixes it; repeated cancellation verifies no queued work remains.
6. Review findings addressed: invalid timeout category, case-ID tags, runtime-cost filtering and DB trial-count protection, foreign action-owner rejections and bounded invalid comparison positions in Views. Zero trial count is prevented by the database constraint; its additional numeric guard is defensive.
7. One full precommit run overlapped the review's full DB suite and timed out an unchanged legacy coordinator-restart test. The reviewer also observed pool contention. A serialized precommit rerun passed all 864 cases without changing that legacy test. No exclusion or timeout was added.

## Changed files and scope boundary

Owner: `study.ex`, `study/workflow.ex`, `study/lifecycle.ex`, `study/pilot/analysis.ex`, `study/views.ex`, read/link helpers in `study/persistence.ex`, `study/persistence/{collection,executions}.ex`, Pilot policy/workflow cases and evidence/checkpoints.

Worker scaffold: `pilot/analysis_contract.ex`, Pilot Analysis DAG/actions, shared action-boundary helper, RunMonitor, one application child, monitor and contract cases. Both old and new action boundaries retain their required external interfaces.

Tooling: `src/.credo.exs` and `src/.formatter.exs` include `scripts/`. Goal 02 dependencies, numerical source and tests remain verified.

Final collection, domain timing, Final analysis, complete study commands, full statistical calibration and retirement remain later milestones. Current Final continuation returns an explicit bounded unavailable result; no feature flag, compatibility machinery or Python fallback conceals that scope.

## Final completion audit

The owner inspected the source, discriminating regression cases, real JSON artifacts, persisted report read, Repo targets, development identity digest, helper/service cleanup and the final full gate for every checklist row. The final reviewer approved execution-first locking, cancellation ownership, existing-link idempotence, own-run cleanup and proof integrity. Its focused run passed 12 workflow cases plus 10 collection regressions.

The last serialized `mix precommit` returned exit 0 at 16:00:28Z with **867 passed, 2 excluded**, no Credo findings across **709 source files**, and successful Dialyzer analysis. The single existing Gust type warning remains the original ignored warning; no warning filter was added. The default two RabbitMQ exclusions remain unchanged; the required real Pilot used RabbitMQ directly.

Two accepted design limits remain visible: active-run stopping is best-effort after durable cancellation, and an unfenced stop failure can remain silent. Durable cancellation and proof rejection remain authoritative. The positive-trial database constraint protects the cost helper's defensive zero-trials guard. These are documented limits, not missing Pilot deliverables.

All helpers finished. The owned temporary broker is absent. There is no owned background execution to stop. No required Goal 03 work remains.

**Audit result: Goal 03 is verified complete. The combined Goals 02–03 objective is achieved within its original shared deadline. Goals 04–06 remain unstarted.**
