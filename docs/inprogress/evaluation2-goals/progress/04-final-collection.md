# Goal 04 — Final collection

## Outcome and clock

- UTC start: **2026-10-31T16:53:08Z**.
- Immutable deadline: **2026-10-31T19:53:08Z**, exactly 10,800 seconds after start.
- Reserved checks/reporting window: **19:38:08Z**. Work finished early.
- Completion audit UTC: **2026-10-31T17:39:29Z**. Elapsed at audit: **46 minutes, 21 seconds**.
- Cleanup and reporting check UTC: **2026-10-31T17:43:48Z**. Total elapsed: **50 minutes, 40 seconds**.
- Status: **verified complete for Goal 04**.

The delivered boundary is an accepted Final Collection snapshot and its durable `analyzing_final` successor. Goal 05 owns native Final analysis and whole-study success.

## Assignments and ownership

| Helper | Model and bounded scope | Outcome |
|---|---|---|
| `goal04-scout` | scout; read-only prerequisite, source and contract inspection | Goals 01–03 evidence and current Final gaps identified |
| `final-tier-dag` | worker, `deepseek/deepseek-flash`; static tier DAG, thin actions and focused cases | Delivered; a bounded follow-up removed duplicate effect adapters |
| `final-contract-fixtures` | worker, `deepseek/deepseek-flash`; strict result codec, transient TierRun and independent clock cases | Delivered; 19 independent cases passed |
| `goal04-review` | reviewer, `deepseek/deepseek-flash`; independent prototype source/test review and final artifact audit | **APPROVE**, both initial review and final follow-up; final independent 42-case slice passed |

Both scaffold workers received the same absolute deadline and instructions to check and address Credo and linter findings. No helper delegated recursively. All helpers finished.

The owner implemented the clock/session state machine, application child, Final plans, scientific equality payload, representative evidence, canonical tier progression, completion proof, resume provisioning and acceptance integration. Existing Persistence transactions retain lifecycle ownership.

## Concrete success criteria

1. Start after the verified Goals 01–03 milestone.
2. Execute small, medium and large tiers sequentially through canonical Gust links.
3. Execute one warm-up and five measured replicas per tier, with stable scientific seeds and fresh physical effects.
4. Store complete durations in Gust results. Keep raw monotonic readings in memory.
5. Reject lost incomplete clock sessions and scientifically unequal replicas without replacement work or invented times.
6. Prepare the Final snapshot after equality checks. Accept it through the existing locked Persistence transition.
7. Rebuild completed timing from durable receipts after the caller and clock process are gone.
8. Verify the behavior with focused cases, real retained services, static checks and independent review.
9. Preserve accepted evidence, unrelated work/data and shared services. Keep Final analysis and retirement outside this milestone.

## Prompt-to-artifact completion audit

Paths in this table are relative to `src/` unless stated otherwise.

| Explicit requirement | Inspected artifact and direct evidence |
|---|---|
| Goals 01–03 pass first | Their checkpoint audits record scoped completion. Before implementation, the current `test/network_defense/evaluation2` folder passed **229 cases**, including numerical and Pilot behavior. The final full gate also covers that scope. |
| Read AGENTS, goal README and linked contracts | AGENTS, goal sequence/safety rules, refactor sketches/brief, behavior test plan, statistical method/checks, prototype review policy, phase types and actual Persistence owners informed the implementation and both independent reviews. |
| Immutable three-hour deadline, workers, checks and reporting | Clock and assignments above. The deadline never changed. Commands used bounded timeouts within the remaining allowance. Reporting finished early; no deadline stop or operator pause is needed. |
| One or two initial scaffolding workers; substantive owner implementation | Two disjoint scaffold workers supplied DAG/actions and codecs/fixtures. The owner implemented the substantive clock, equality, evidence, progression and acceptance logic. |
| Worker model and Credo/linter requirement | Both workers used `deepseek/deepseek-flash`. Their checks and the owner integration gate cover formatter, strict Credo and Dialyzer. Findings were fixed without new suppressions. |
| Static reusable Final tier DAG and thin actions | `priv/gust/dags/evaluation2_study_final_tier_collection.exs` declares **35 tasks**. Actions under `study/workflow/final_tier_collection/actions/` bind the acting run, call existing capabilities and persist receipts. Loader/topology/action cases and the actual development runs exercise this path. |
| Sequential tiers and canonical create-link-dispatch | `study/workflow.ex` derives the completed prefix from `Tier.all/0` and canonical PhaseRuns. The existing authoritative Gust row lock serializes dispatch. Repeated provisioning and two concurrent continuations converge on one run per tier. The real tier runs are **6 / 7 / 8**. |
| One Workflow loop and no stored tier cursor | Workflow retains caller-owned progression. Source audit found no tier cursor, second Final runner or `Final.Collection.run/1`. RunMonitor remains wait-only; Timing owns no progression. |
| Resume freezes selection and ensures the first run | `study.ex` commits approval through `Executions.accept_approval/2`, then ensures the first canonical run. FLOW/BIND cases and the actual explicit insufficient override prove small-tier provisioning before continuation. |
| One warm-up plus measured positions 0..4 | The DAG completes warm-up `-1` before measured replica zero. Each measured completion enables the next replica. The real artifact records positions **-1, 0, 1, 2, 3, 4** for every tier, with three physical items per batch. |
| Stable scientific seeds; fresh physical effects | `Collection.prepare_final/4` resolves one tier plan with Final phase roots. Replica coordinates do not enter seed derivation. COL-03/RNG-02 checks seeds and unique links. The real Final collection has **54 distinct items, 54 optimization runs and 54 experiments**, with no links shared across replicas. Item retry still uses existing reservations. |
| Application-owned, execution-side clock sessions | `application.ex` supervises `Final.Timing`. The prepare action opens a session in the execution runtime and stores its token. Later actions recover that stored token and never open replacement sessions. The continuation caller does not start or own the clock. |
| Explicit complete-batch timing boundaries | Measured tasks call plan-start, the shared plan-completion/simulation-dispatch boundary, then replica-end. Queue and task retry delay inside those boundaries remain measured. TIME-01 uses independent controlled microsecond readings and checks marker ordering and retry idempotence. |
| Raw monotonic readings stay in memory | `final/timing.ex` keeps readings only in GenServer state. Strict codecs persist only completed plan-selection, simulation and total durations, with five measured positions. Warm-up contributes no measured receipt. |
| Durable completed proof and safe cleanup | `TierContract.Output` binds phase run, tier, clock session and five duration triplets. Workflow checks the exact input, canonical link, succeeded run, unique succeeded terminal, prepare binding and each stored replica receipt before release. Cleanup occurs after durable proof; later reads use Gust. |
| Lost in-progress clock fails; no invented or replacement measurements | TIME-03 restarts the supervised clock behind a controlled measured-work barrier. A separate real RabbitMQ-backed interruption also fails after `mark_plan_start_0`. Both leave no completed replica-zero receipt, replica-one items, snapshot or analysis successor. |
| Scientific equality with only permitted exclusions | `Collection.replica_observations/2` retains frozen input identity, requests, settings, seeds, selected action targets/costs, logical graph nodes/edges and full attacker-state evolution. It excludes physical run/output revision IDs, timestamps and durations. TIME-04 accepts fresh matching effects and rejects changed action targets and changed attacker outcomes that leave primary mission impact unchanged. |
| Complete and ordered representative evidence | `Final.Collection.prepare_snapshot/2` checks all tiers, warm-up source completeness and measured equality. It projects replica zero through the pure `Collection.project_evidence/3`. COL-04 rejects missing trials. The real snapshot contains **six comparisons**, each with one row per side and two aligned attack columns; each tier shares one CVSS group. |
| Snapshot preparation distinct from lifecycle acceptance | Final.Collection writes the prepared snapshot only after validation. Workflow then calls `Persistence.Executions.accept_final_collection/1`. Integration cases show preparation leaves `collecting_final` with no successor until acceptance. The existing transaction creates the durable `analyzing_final` successor. Repeated acceptance remains idempotent. |
| Strict completion binding and cancellation fences | BIND-02 rejects a successful terminal naming another tier. Existing Pilot cases retain foreign input/snapshot and link-cancellation coverage. Final cancellation leaves cancelled state and creates no next tier or analysis successor. |
| Timeout returns current Status | A controlled enqueued Final run remains `collecting_final` after bounded continuation. No failure, cancellation or additional tier is created. Timeout remains an API wait bound. |
| Completed reads after caller and clock loss | TIME-02 restarts the application clock after concurrent callers finish. A later normal application VM, in Gust console role, independently decodes all **15 receipts**, returns the same snapshot and rebuilds timing at **17:33:29Z**. |
| Environment and known-contract checks | Revision creation freezes `evaluation2-goal04-local` for the real run. Final boundaries reject missing/changed environment labels and known method/seed contract mismatches. A fresh validation revision preserves the older Pilot's frozen provenance. The label is a deployment assertion, not authenticated hardware identity. |
| Compile and focused COL/BIND/FLOW/TIME gates | Folder gate: **282 passed**. Explicit `mix compile --warnings-as-errors`, strict Credo and formatter checks pass. The serialized precommit gate passes **920 cases, 2 excluded**. The reviewer independently ran 42 Final clock/contract/DAG/action cases. |
| Real small-tier/collection-prefix evidence with canonical links and receipts | The normal application and retained RabbitMQ executor completed all three tiers, stronger than the minimum prefix evidence. The JSON artifact records the canonical phase/run/plan/effect links, every replica and every completed receipt. |
| Goal 05 owns remaining analysis; no whole-study success claim | The accepted execution remains **`analyzing_final`**. Continuation reports the bounded `final_analysis_not_implemented` boundary. No successful whole study, native Final result or full statistical calibration is claimed. |
| No public staging API or temporary framework | The Study facade gained no staging operation. Final.Collection prepares evidence; Workflow orchestrates; Persistence accepts; Timing measures. The only shared extraction is a small stateless effect adapter in the existing ActionBoundary. |
| Preserve evidence, unrelated work/data and services | The previous real Pilot still reads `awaiting_final`. Five original development graph revisions retain their ordered identity digest. Existing worktree changes, including the separately added Goal 05.5 plan, remain. Shared graph/optimization/simulation/compute APIs and services are unchanged. |
| Authorized local test DB after target checks | Both Repos were checked as **localhost:5433 / network_defense_test**, postgres, SQL Sandbox, password present, before DB tests. Manual checks separately verified **localhost:5433 / network_defense_dev**. |
| No reset, commit, infrastructure apply or early retirement | No reset, migration, commit, Terraform apply or retirement occurred. HEAD remains **`683335c`**. The only temporary service was the owned broker, now removed with its owned volume and generated configuration. |
| Fix material failures first and rerun affected cases | Red collection/workflow cases preceded implementation. Integration defects and lint/type findings were corrected, followed by the 282-case folder gate and final serialized full precommit. Details follow. |
| Blocker/deadline stop policy | No current-slice blocker remains. All helpers and owned runtime work finished before the original deadline. No successor goal started. |

## Real development evidence

### Accepted collection

- Frozen revision: **`evaluation2-final-20261031`**, revision **1**.
- Execution: **`f48d83a5-343e-4c59-b8b3-7f37bdfec739`**.
- Pilot outcome: **insufficient**. Approval explicitly used `override_insufficient` with candidate **tiny**.
- Frozen counts: **one plan per side / two attacks per plan**.
- Configured label: **`evaluation2-goal04-local`**.
- Runtime: normal application, Gust **single** role, retained **RabbitMQExecutor** and RabbitMQ worker.
- Final tier Gust runs: **small 6 / medium 7 / large 8**.
- Accepted Final snapshot: **`aa5bf855-97c1-4005-ac71-3115146e2c5e`**.
- Durable Final Analysis successor: **`7c076f1b-53a5-4ddb-95ee-bc5d923d3c06`**.
- State: **`analyzing_final`**.

Artifact:

`local-results/evaluation2-final-collection-f48d83a5-343e-4c59-b8b3-7f37bdfec739.json`

The artifact includes all six batches per tier, unique physical effect identities, canonical links, 15 duration triplets and six representative comparison matrices. A later VM verified the same persisted terminal receipts and snapshot. These small counts demonstrate the collection protocol; they do not establish useful statistical precision or calibration.

### Actual clock interruption

- Execution: **`3523a833-da11-43af-a0af-c1194f3b9872`**.
- Canonical small-tier PhaseRun: **`731dc607-1b82-475a-b805-6170bdf9e2e8`**; Gust run **11**.
- A durable task-state barrier observed succeeded `mark_plan_start_0` before the simulation boundary.
- The probe terminated and restarted the application-owned clock. The replacement rejected the old session.
- The normal DAG failed the tier. Durable state is **failed**, with one canonical tier link, zero replacement replica-one items, zero completed replica-zero receipts, no snapshot and no Final Analysis successor.
- Repeated continuation retains failed state and creates no replacement run.

Artifact:

`local-results/evaluation2-clock-loss-3523a833-da11-43af-a0af-c1194f3b9872.json`

## Checks and commands

Commands ran from `src/` unless stated otherwise. The disposable environment helper loaded `src/.env`, selected localhost:5433 and used the mounted PostgreSQL/RabbitMQ password files. Secret values were omitted from logs and this report. The helper and real-run scripts were removed after verification.

| Exact check | Result and evidence |
|---|---|
| Both Repo configurations, test, via `MIX_ENV=test mix run --no-start` | Verified local target and SQL Sandbox before DB use; `/tmp/evaluation2-goal04-targets.log` |
| Both Repo configurations, development, via `MIX_ENV=dev REPO_DATABASE=network_defense_dev mix run --no-start` | Verified local target before manual work; `/tmp/evaluation2-goal04-dev-targets.log` |
| Read-only development status and original-identity queries | Before execution startup: two succeeded / one failed Gust runs, zero queued/active work; `/tmp/evaluation2-goal04-dev-before.log` |
| `MIX_ENV=test timeout 120 mix test test/network_defense/evaluation2` | Baseline **229 passed**; `/tmp/evaluation2-goal04-baseline.log` |
| Initial Final collection/workflow cases | Failed at the intended unimplemented boundaries; `/tmp/evaluation2-goal04-{collection,workflow}-red.log` |
| `MIX_ENV=test timeout 100 mix test test/network_defense/evaluation2` | **282 passed**, exit 0; `/tmp/evaluation2-goal04-suite.log` |
| `timeout 60 mix compile --warnings-as-errors` | Exit 0 on final source; `/tmp/evaluation2-goal04-compile.log` |
| `timeout 60 mix credo --strict --format flycheck` | Exit 0, no findings; `/tmp/evaluation2-goal04-credo.log` |
| `mix format --check-formatted`; root `git diff --check` | Both pass; `/tmp/evaluation2-goal04-format.log` and final owner check |
| `MIX_ENV=test timeout 240 mix precommit` | **920 passed, 2 excluded**, exit 0; `/tmp/evaluation2-goal04-precommit.log`. Includes generated contracts, Elixir/frontend formatting and type checks, strict Credo, Dialyzer, Sobelow and dependency checks. |
| Reviewer independent Final clock/contract/DAG/action slice | **42 passed**, exit 0; final follow-up review |
| `MIX_ENV=dev REPO_DATABASE=network_defense_dev GUST_ROLE=single EVALUATION_MEASURED_ENVIRONMENT_REVISION=evaluation2-goal04-local timeout 300 mix run --no-start /tmp/evaluation2-goal04-real-collection.exs` | Exit 0; script starts the normal application, reaches the accepted collection boundary and writes the real artifact; `/tmp/evaluation2-goal04-real-collection.log` |
| Same normal startup, `timeout 150 mix run --no-start /tmp/evaluation2-goal04-real-clock-loss.exs` | Exit 0; actual incomplete-clock failure and no replacement; `/tmp/evaluation2-goal04-real-clock-loss.log` |
| `MIX_ENV=dev REPO_DATABASE=network_defense_dev GUST_ROLE=console EVALUATION_MEASURED_ENVIRONMENT_REVISION=evaluation2-goal04-local timeout 60 mix run --no-start /tmp/evaluation2-goal04-read-completed.exs` | Exit 0; later VM and fresh clock read all 15 receipts at 17:33:29Z; `/tmp/evaluation2-goal04-durable-read.log` |
| Final read-only development safety query | Five originals unchanged; successful collection `analyzing_final`; interrupted execution failed; previous Pilot `awaiting_final`; Gust **nine succeeded / two failed**, zero queued/active; `/tmp/evaluation2-goal04-dev-final-safety.log` |

The two default RabbitMQ test exclusions remain unchanged. Required real collection and interruption checks used RabbitMQ directly. Dialyzer reports only the existing ignored Gust warning; no new ignore was added. Runtime contract generation emits module-redefinition notices, while the explicit compiler check and the complete gate both pass.

## Changed files

- Owner: `study.ex`, `study/{collection,definition,workflow}.ex`, `study/final/{collection,timing}.ex`, and the clock child in `application.ex`.
- Scaffold: `study/final/tier_contract.ex`, `tier_contract/output.ex`, `tier_run.ex`, the new Final tier DAG and its action directory.
- Shared lint correction: `study/workflow/action_boundary.ex` and the two existing Pilot effect actions.
- New cases: `final_collection_test.exs`, `final_workflow_test.exs`, `final_timing_test.exs`, `final_tier_contract_test.exs`, and the Final tier action/topology/loader test files.
- Test support: `test/support/evaluation2_final_fixtures.ex`; the existing Pilot workflow case now checks Final provisioning at its delivered boundary.
- Documentation: this checkpoint and a narrow status/evidence update in the goal README. Its separately added Goal 05.5 content remains intact.

## Findings and fixes

1. Initial Final planning compared atom tier keys with string definition tiers and produced empty plans. The failing physical-row assertions exposed it. Planning now uses the declared tier representation; the full effect/evidence cases pass.
2. Final progression initially classified a missing row after public error mapping. The mapped category was unavailable, so no first tier was created. Classification now uses the internal not-found kind before mapping. Provisioning, concurrency and real approval pass.
3. The generalized failure path temporarily changed the existing Pilot error code. The Pilot regression caught it; Pilot retains its established code, with a separate Final code.
4. A separate Final assembly helper could insert a snapshot before equality. Review prompted its removal. Final.Collection now inserts only after validated replica representatives pass pure projection.
5. Repeated Pilot/Final effect adapters triggered duplicate-code findings. A bounded worker follow-up extracted identical mechanics into the existing stateless ActionBoundary. Phase-specific messages and bindings remain intact.
6. Strict Credo found nested branches, undocumented internal entrypoints and test aliases/count assertions. The owner simplified branches, documented the shared capability and corrected the cases. Final Credo is clean.
7. The first full gate found a range return typespec written as an integer range and a tagged-error spec that excluded tuple causes. Correct specs restored reachable error branches. The serialized precommit rerun passed without suppressions.
8. Boundary receipt decoding now checks total equals plan plus simulation. Final actions also reject known method/seed contract changes. Warm-up source completeness is checked before snapshot preparation.
9. The initial independent review and final follow-up both returned **APPROVE**. Accepted prototype limits include transient released-session bindings and repeated prefix reads. Production multi-node hardening remains outside this milestone.

## Preservation and cleanup

- Five original non-optimization development revisions retain digest **`4af8a731783d517d7c39a80a26adfd700e35bf3b14028401f03f4380a96ceef9`**, over ordered revision/graph IDs. Before and after rows compare equal.
- Previous Goal 03 evidence remains intact. New accepted and failed validation executions remain as durable evidence.
- The owned broker container **`evaluation2-goal04-rabbitmq`** was identified by its exact container ID before removal. Its anonymous volume and generated configuration were removed. Shared containers were untouched.
- Disposable probe scripts, execution-ID files and the environment helper were removed. All **17 owned logs** were scanned against the mounted PostgreSQL/RabbitMQ secret values: **zero hits**. Non-secret check logs and durable JSON evidence remain.
- No reset, migration, commit, infrastructure apply or legacy retirement occurred. The separately added documentation Goal 05.5 and other pre-existing worktree changes remain.
- All helpers finished. No owned background execution or temporary service remains.

## Final audit decision

The owner checked current source, discriminating positive/negative cases, the full gate, real canonical links and receipts, later-VM reads, the actual clock-loss failure, independent review, local targets and cleanup for every checklist row above.

**All Goal 04 requirements are achieved.** The next permitted milestone is Goal 05, starting from the durable `analyzing_final` boundary. Native Final analysis, whole-study success, full statistical calibration, documentation Goal 05.5 and legacy retirement retain their separate owners and gates.
