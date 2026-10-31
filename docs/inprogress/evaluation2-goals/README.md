# Evaluation2 implementation goals

This delivery plan supersedes the earlier single-batch execution decision. The consolidated refactor brief remains the scope reference; execute the six goals below in dependency order.

**Status: Goals 01–05 verified. Goals 05.5 and 06 have not started.**

[Goal 01 evidence](progress/01-foundation.md) records the requirement audit, setup fixes, review, and passing checks. The [Goal 02 numerical audit](progress/02-native-numerics.md) and [Goal 03 Pilot audit](progress/03-pilot-workflow.md) record the later scoped gates. The [Goal 04 collection audit](progress/04-final-collection.md) records real sequential Final tiers, durable timing/equality proof and the accepted snapshot at `analyzing_final`. The [Goal 05 audit](progress/05-native-study.md) records native Final analysis, two real successful all-tier executions, public result reads and 990 passing regression cases. It also records the worker's default port-5432 test-database deviation and the operator's confirmation that both targets are development environments, which resolves the preservation gate. Goal 05.5 is next. Full calibration, documentation refresh and retirement retain their later gates.

## Sequence

| Goal | Verified milestone | Owner's substantive work | Initial scaffolding workers |
|---|---|---|---|
| [01 — Foundation](01-foundation.txt) | New definition persists/reloads and existing Pilot collection works with grouped requests | Constructor, policy/seed derivation, consumer adaptation, collection correctness | Types/schema; behavior fixtures/test bootstrap |
| [02 — Native numerical core](02-native-numerics.txt) | Selected matching/betting method and precision helpers pass focused mathematical checks | Betting, intervals, comparison, Holm, planning arithmetic | Matching/input scaffolding; independent math cases and validation-runner shell |
| [03 — Pilot and continuation](03-pilot-workflow.txt) | Real Pilot reaches awaiting_final with a complete report | Caller-owned workflow, canonical completion, Pilot policy and facade | Pilot DAG/actions/codecs; monitor/supervision/test scaffolding |
| [04 — Final collection](04-final-collection.txt) | All tier collections have durable timing/equality proof and an accepted Final snapshot | Clock sessions, replica validation, tier progression and acceptance | Tier DAG/actions; timing/result contracts and fixtures |
| [05 — Complete native study](05-native-study.txt) | Explicit approval drives native Final analysis to a durable result | Final scientific preparation/acceptance, result reads, CLI integration and real study | Analysis DAG/contracts; thin commands/report views |
| [06 — Verification and deletion](06-verify-and-delete.txt) | Scientific/regression evidence passes and the obsolete implementation is absent | Verification, defect correction, actual deletion and final audit | Calibration fixtures/runner completion; retirement manifest/audit scaffolding |

Each goal has a **3-hour total elapsed-time budget**. The planned sequence therefore has an 18-hour maximum allocation if all six milestones finish within their original budgets. This is not a completion-time guarantee. An unmet goal blocks its successors and needs an explicit follow-up plan.

## Owner and worker rules

1. Each goal has one implementing owner.
2. At the start, the owner gives **one or two workers** bounded scaffolding tasks with explicit file ownership and interfaces.
3. The owner then implements the substantive critical-path logic. It must not become a passive dispatcher or delegate the complete goal.
4. Workers do not recursively fan out. Avoid overlapping file edits; transfer ownership explicitly before integration.
5. The owner integrates the scaffolding, runs checks, addresses material review findings, and writes the completion evidence.
6. Independent review can run after scaffold workers finish. It does not replace owner implementation.

Scaffolding means useful types, codecs, DAG/action wiring, test fixtures, or runner structure. Empty placeholders are not a completed milestone.

## Three-hour deadline

On first execution, record UTC start and deadline (`start + 10,800 seconds`) in the goal's checkpoint file. Give workers that same absolute deadline. Resume/compaction does not reset it. Include worker time, dependency/setup work, tests, reviews, and reporting in the budget.

Reserve the final 15 minutes for bounded checks and handoff. Apply remaining-time limits to commands. Stop unfinished helpers and owned background work by the deadline. At expiry, report incomplete scope and evidence; do not mark an unfinished goal complete or silently carry on under the same clock.

**Runtime limitation:** the installed pi-goal documents `/goal [--tokens ...]`, pause/resume, and completion, but no wall-clock cutoff flag. These prompts enforce a work deadline by instruction. Automatic process cutoff requires an external runner/watchdog; an unmet active goal must be paused by the operator/runtime. Do not invent `/goal --timeout` or mark partial work complete to escape continuation. No timer extension is implemented by this plan.

## Dependency and verification gates

- Start a goal only after its predecessor's scoped completion evidence passes.
- Intermediate goals are explicit milestones, not claims that the whole system works. In particular, Goal 04 does not claim Final analysis is implemented.
- Preserve working behavior inside completed scope. Leave unrelated future placeholders clearly identified; do not introduce temporary feature flags or compatibility adapters to conceal missing work.
- Use TDD and the named behavior cases. Each goal records exact commands and results, file changes, and remaining limitations.
- Keep the full statistical checks for Goal 06. Earlier smoke checks are not empirical calibration passes.
- Use fresh local validation executions when frozen provenance is incompatible. Never weaken provenance checks to resume an old fixture.

## Safety and scope

Read `AGENTS.md`, `docs/inprogress/evaluation2-refactor-sketches.md`, `docs/inprogress/evaluation2-full-refactor-brief.md`, `docs/inprogress/evaluation2-test-plan.md`, `docs/inprogress/evaluation2-statistical-validation.md`, and `docs/inprogress/evaluation2-statistical-checks.md`.

The latest goal plan overrides only the prior delivery granularity and adds deadlines/fan-out rules. Scientific, ownership, testing, reset, and retirement-verification decisions remain in force.

- Preserve pre-existing worktree changes, credentials, unrelated user data, and graph/optimization/simulation/compute infrastructure.
- No commits, development reset, remote/production database operations, or Terraform apply without explicit permission.
- Isolated local `network_defense_test` is authorized. Verify both Repo targets and local connection settings before setup. Manual real-study verification uses development.
- New format only; no old readers, alias facades, numerical stream compatibility, or migration adapters.
- Snapshot preparation and lifecycle acceptance have different owners. Keep one Workflow progression loop and the existing Persistence transaction owners.

## Retirement: MUST DELETE

After the native verification gate passes, **MUST DELETE the obsolete implementation as if it did not exist in the active project**:

- Legacy evaluation facade, pipelines, analysis clients, tasks, DAG sources, and registrations.
- Python evaluation_compute service tree and obsolete evaluation/analysis artifacts.
- Obsolete wire schemas, fixtures, tests, legacy-only migration/setup sources, service-only dependencies, environment bindings, and deployment-source wiring.
- Dead compatibility branches, unused superseded scaffolds, stale approved legacy DAG definitions, and project-local compiled/cache artifacts of retired modules.
- Current usage/documentation that instructs callers to use the retired implementation.

No disabled copy, renamed archive directory, compatibility wrapper, forwarding alias, empty stub, fallback to Python, or “remove later” TODO satisfies this goal. The retained application must compile and work after deletion.

Require a zero-leftover audit of implementation/configuration/test/build/dependency/deployment-source surfaces in the agreed scope. Explicit historical decision records, scientific citations, and this removal plan can mention the past implementation; they must contain no retained runtime path. Do not rewrite Git history or purge unrelated/irreplaceable data.

Include persisted legacy-only artifacts in the exact retirement manifest as well. Use only authorized local cleanup; verify ownership and data impact before any deletion. Never infer ownership from a broad name prefix that could match Evaluation2 or shared objects.

Do not delete before native verification. If a required deletion would destroy protected data or require an unauthorized operation, report the exact blocker and leave the goal unmet. Do not silently drop the leftover from scope to claim success. Never label incomplete retirement as complete.

## Checkpoint record

Each owner writes `docs/inprogress/evaluation2-goals/progress/NN-<goal>.md` with:

- Start/deadline, worker assignments, and elapsed time.
- Scoped outcome and changed files.
- Exact checks and results, with credentials omitted.
- Review findings and fixes.
- Complete/unmet/blocked status, remaining work, and the next needed action.

Do not start any of these goals merely by drafting this file. Paste the corresponding single `/goal` command when execution is approved.
