# Goal 05 — Native study

## Status and clock

**Goal 05 complete.** The native full-path milestone passes its technical audit. The operator confirmed that both database targets are development environments, resolving the preservation gate. Goal 05.5 is next; Goal 06 still waits for the documentation refresh.

- Start (UTC): **2026-10-31T19:18:27Z**.
- Deadline (UTC): **2026-10-31T22:18:27Z**, exactly 10,800 seconds after start.
- Reserved regression/reporting boundary: **2026-10-31T22:03:27Z**.
- Final evidence recheck: **2026-10-31T20:22:59Z**, 1 hour 4 minutes 32 seconds after start. The original deadline remains unchanged.
- Resume does not reset the clock. Workers, reviews and checks received the same deadline.
- All helpers finished. The owned broker and its anonymous volume are removed. No owned execution remains active. Work reached the reporting boundary early; the final 15-minute reserve was not consumed.
- Operator clarification: “Relax, its dev environment both of them.” This confirms the development scope of both targets and resolves the reported preservation gate. No further database operation, rollback or credential change was performed.

## Concrete deliverables

1. Explicit Final approval drives a new-format study through native Final analysis and atomic result/succeeded acceptance.
2. Public result reads return the owning execution's typed family and measured timings.
3. Thin commands cover create, Pilot, Final approval, continue, status, Pilot report, result and cancel.
4. Compile, scientific/Holm, completion, result, command, lint and regression checks pass.
5. A real development study completes all tiers and the fixed warm-up/five-replica protocol. Evidence records actual effects, graphs, counts, identities and approval intent.
6. Provenance and identity checks, earlier evidence, unrelated changes, services and credentials remain protected. Any deviation requires an explicit report and operator decision.
7. Documentation refresh and retirement retain their later gates.

## Assignments and ownership

- `final-analysis-scaffold`, **deepseek/deepseek-flash**: Final Analysis codecs, DAG, thin actions and independent contract/action/topology/load cases. Follow-up added real Persistence/Gust binding cases and prepared-batch identity checks.
- `study-command-scaffold`, **deepseek/deepseek-flash**: thin Mix commands, startup/formatting helper and independent command cases. Follow-up changed cancel to non-dispatching startup and rejected duplicate approval flags.
- Both workers received the shared deadline and the instruction to check and address **Credo and linter findings**, without new suppressions. They performed no recursive delegation.
- Owner: scientific preparation/evaluation/correction, Workflow completion, acceptance-time provenance checks, timing reconstruction/integration, transaction and result cases, real studies and audit.
- Search-only scout checked Goal 01–04 evidence and current interfaces. Independent reviewer returned technical **APPROVE** after the Pilot identifier fix. Preservation approval remains separate.

## Prompt-to-artifact audit

Source paths below are relative to `src/` unless stated otherwise. A green check is supporting evidence only; each row names the behavior it covers.

| Explicit requirement | Inspected artifact and evidence | Status |
|---|---|---|
| Goals 01–04 pass first | Their four checkpoint audits establish the prerequisite milestones. The final 990-case precommit includes the retained native numerical, Pilot and Final collection cases. The previous Goal 04 execution still reads `analyzing_final`. | Verified |
| Read AGENTS, goal README and linked contracts | AGENTS, the goal plan, refactor sketches/brief, behavior test plan, statistical validation/checks, prototype review policy and current phase/Persistence interfaces informed the implementation and independent review. | Verified |
| One or two bounded scaffolding workers with owner implementation | Two disjoint workers supplied codecs/actions/DAG and thin commands. The owner implemented `Final.Analysis`, Workflow completion and acceptance integration, and the substantive scientific/transaction cases. | Verified |
| Worker model and Credo/linter instruction | Both workers used `deepseek/deepseek-flash`. Targeted worker checks and the final strict Credo, formatter and Dialyzer gates pass. No new suppressions were added. The pre-existing `.credo.exs` change was preserved. | Verified |
| Three-hour immutable clock, shared deadline and final 15 minutes | UTC times above differ by exactly 10,800 seconds. Every assignment used the same absolute deadline. Helpers and owned runtime work finished before the reserved period. | Verified |
| Static native Final Analysis DAG | `priv/gust/dags/evaluation2_study_final_analysis.exs` declares prepare → mapped comparison evaluation → `correct_final_family`. Topology/load cases and actual Gust runs 17 and 24 exercise it. | Verified |
| Strict codecs and thin actions | `study/final/analysis_contract.ex` checks exact keys, UUIDs, closed scientific literals, finite/ranged values and nested typed shapes. Actions under `workflow/final_analysis/actions/` bind the acting run and call the capability. Contract/action/load cases cover malformed payloads and foreign runs/phases/snapshots. | Verified |
| Scientific job preparation from accepted Final evidence | `Final.Analysis.prepare/1` requires the Final Analysis successor as the acceptance witness, complete comparison membership, frozen dimensions and derived attack seeds. The prepared snapshot alone fails the focused acceptance-witness case. | Verified |
| Matching-based evaluations in model units | `Final.Analysis.evaluate/2` loads canonical matrices and the frozen tier bound, then calls the retained pure `Compute.compare/2`. Independent sequential numerical anchors check the typed estimate, interval and marginal p-value. Invalid position, seeds, shape and out-of-bound outcomes fail. | Verified |
| Complete canonical family and Decimal Holm correction | Mapped results retain comparison positions. The fan-in requires succeeded tasks and the exact prepared position set. `Final.Analysis.correct/2` checks the frozen count, method, confidence, range and assessment policy, then calls `Compute.holm/2`. HOLM-01 covers order, ties, capping, inclusive Decimal decisions and float consistency. | Verified |
| Terminal scientific validation | `Final.Analysis.validate_output/2` checks method/seed compatibility, complete typed statistics and exact recomputed Holm adjustments/decisions. Changed contracts, invalid confidence/probabilities and inconsistent decisions fail. | Verified |
| One caller-owned Workflow loop | `Workflow` now progresses `analyzing_final` through the same canonical create-link-dispatch/wait/proof/accept loop. It adds no coordinator, cursor, alternate runner or background progression service. | Verified |
| Canonical run/input/snapshot and unique succeeded terminal | `Workflow.final_analysis_result/1` proves canonical phase link, exact run input including accepted snapshot, succeeded run, one succeeded terminal and typed valid output. Cases reject foreign acting run, wrong phase, another execution's snapshot, Pilot snapshot, foreign root snapshot and malformed terminal. | Verified |
| Timing reconstruction with no Mix clock logic | `Workflow.final_timing/1` reconstructs all three canonical tier receipts. Acceptance uses these durations. Later normal-application VMs and fresh clock processes reconstructed all 15 triplets, including after broker removal. Commands contain no clock logic. | Verified |
| Final provenance recheck at acceptance | `Final.Analysis.validate_provenance/1` runs for scientific work and immediately before result acceptance. A controlled label change after correction leaves `analyzing_final` with no result. Restoring the label accepts the same completed run. | Verified |
| Atomic result and succeeded state | The existing `Persistence.Executions.accept_final_analysis/3` transaction remains the owner. FLOW-05 injects a rejected success transition after insertion and proves rollback of both result and state. Retry, concurrent equal acceptance and conflicting output cases retain one result. | Verified |
| Public typed result reads and unavailable boundaries | `Study.result/1` and `Views.result/3` join the owning revision, Pilot outcome, selection, corrected family and timing. RESULT-01 checks the joined identities and bounded pre-success result. Real command reads also prove unavailable result/report before their boundary. | Verified |
| Cancellation, timeout and re-entry | Retained FLOW-03/FLOW-04 cases remain green. Final Analysis is included in best-effort stopping. The real queued command probe proves inspection leaves work enqueued and cancellation creates no effects. Re-entry of successful native studies returns the stored result. | Verified |
| `mix study.create` and `mix study.pilot` | Real commands created `evaluation2-native-20261031`, revision 1, and completed two Pilot executions. The Pilot command now prints the committed ID before waiting. A failing-first command regression proves the ID remains visible when continuation fails. | Verified |
| Explicit `mix study.final` approval | Missing, duplicate and contradictory flags fail before startup. The first real insufficient Pilot rejected `--recommended`; explicit `--override-insufficient tiny` completed Final. The second execution repeated the explicit override on final integrated source. | Verified |
| Continue/status/report/result/cancel commands | `study.continue`, `study.status`, `study.pilot_result`, `study.result` and `study.cancel` delegate to Study. Focused tests and real CLI invocations cover their behavior. The proposed report command is named `study.pilot_result`. | Verified |
| Normal application startup and execution-capable Gust | Execution commands use the normal application and Gust core/single execution roles. Inspect/create/cancel use console role. A real console-role `study.continue` fails usefully before execution. | Verified |
| Inspection does not claim queued work | Probe `9d6ccd74-1879-4110-8ed3-77f33549d8e8` remained `collecting_pilot` with its run enqueued and zero items after separate status/result/report VMs. Console cancellation then committed cancelled and fenced the queued Gust run as failed, still with zero items. | Verified |
| Compile and relevant analysis/HOLM/FLOW/RESULT/CMD checks | Explicit `mix compile --warnings-as-errors` passes on final source. Native/command integration first passed 350 cases; later guards and the ID regression are included in the final **990 passed, 2 excluded** full gate. | Verified |
| Credo, formatter and linter findings addressed | Full precommit includes strict Credo, formatter, frontend format/type checks, assets, Dialyzer, Sobelow and dependency checks. It exits 0. Dialyzer retains one existing ignored Gust warning; no new ignore was added. | Verified |
| Real new-format all-tier study with actual effects | Two normal development executions used retained `RabbitMQExecutor` and the RabbitMQ worker. Each completed small/medium/large, one warm-up and positions 0..4, 108 Final optimization/experiment pairs, and six 2×3 comparisons. No mocks supplied this evidence. | Verified |
| Revision/execution/result identities, actual counts and graphs | The two JSON artifacts below contain canonical phase/run/plan/effect/result links, every replica, scientific evidence and graph dimensions. The second artifact records the final integrated source run. | Verified |
| Honest verification scale and approval report | Both Pilots were insufficient. Both Final runs used explicit overrides. All six effects are zero, with intervals `[-8, 8]`, raw/adjusted p-values one and no rejection. Counts verify the protocol, not useful precision, power or full calibration. | Verified |
| Model, seed, provenance and identity checks preserved | Collection equality/seed/effect reservation checks remain green. Final analysis checks frozen shape, aligned derived attack seeds, model bounds, method/seed contracts and configured label. Two executions share no physical effects and reproduce identical scientific matrices/family. The label remains an operator assertion. | Verified |
| Earlier committed/durable evidence and original development graphs | The previous Goal 04 execution remains `analyzing_final`. All five original non-optimization graph revision/graph rows are unchanged, with digest `4af8a731783d517d7c39a80a26adfd700e35bf3b14028401f03f4380a96ceef9`. Earlier artifacts remain. | Verified |
| Preserve unrelated dirty-tree work and shared services | The initial dirty paths remain. New edits stay within the listed Goal 05 surfaces and this narrow goal status update. The shared PostgreSQL container retains ID `00b407b7f31f` and remains running. Only the exact owned broker/volume/configuration were removed. | Verified for inspected scope |
| Verify both Repo targets before setup/checks | Owner checks proved both Repos use `127.0.0.1:5433/network_defense_test` and separately `network_defense_dev`. The worker's earlier port-5432 action remains a documented deviation from target verification. The operator confirmed that both targets are development environments and resolved the preservation gate. No baseline comparison is claimed for the earlier action. | Resolved by operator clarification |
| Protect credentials | Mounted credential files were unchanged. A final scan found exact credential values in OTP Repo supervisor reports in six owned probe logs. Those values were redacted; all 42 owner logs now have mode 0600 and a rescan finds zero exact-value hits. The operator received this report and confirmed the development scope. No credential change was requested. | Remediated and disclosed |
| No compatibility API, commit, reset, Terraform apply or retirement | No such operation occurred in owner work or worker reports. HEAD is `5d132ab`, whose commit at 19:14:38Z predates this goal. Legacy runtime/configuration remains for Goal 06. The worker's default test migration is reported separately. | Verified except reported deviation |
| Fix material failures and rerun affected checks | Red scientific/workflow/command/acceptance-label tests preceded fixes. The final full gate passes after resolving an unreachable branch and a real parallel DAG-load race. Review returned technical APPROVE after the identifier fix. | Verified |
| Goal 05.5 and Goal 06 ordering | Neither later goal started. Goal 05.5 may follow this verified native milestone. Goal 06 still waits for documentation refresh and retains its calibration/retirement requirements. | Gate preserved |
| Report blockers without claiming completion | The owner left the goal unmet while the preservation question was open. After receiving the operator's development-environment clarification, the owner rechecked the 990-case regression output, both real result artifacts, compile/read logs and patch whitespace before completion. | Resolved and audited |

## Real development evidence

Definition: `local-results/evaluation2-native-study-definition-20261031.yaml` (retained copy of the submitted YAML-compatible JSON document).

Shared settings: revision **`evaluation2-native-20261031` / 1**, seed **20261031**, family alpha **0.05**, interval confidence **0.95**, label **`evaluation2-goal05-local`**. Each tier uses budget 1, a shared CVSS group, random and simulation-informed alternatives, and scoring trial count 2. Simulation uses two iterations, two maximum attempts and the frozen rule list. Each candidate has two plans per side and three attacks per plan.

| Tier | Graph revision | Hosts | Total nodes | Edges | Frozen mission-impact bounds |
|---|---|---:|---:|---:|---|
| small | `9a6b0346-8d3e-4526-8552-626c8ba831d9` | 16 | 53 | 71 | [0, 8] |
| medium | `4b408c14-575f-44fc-9bd7-71725f5c06a0` | 51 | 135 | 201 | [0, 8] |
| large | `f6944686-ad78-4819-8572-abfae5958ee8` | 101 | 260 | 404 | [0, 8] |

### First full command execution

- Execution: **`d826b08c-8b2a-44b9-b927-d4b0a3b38a43`**.
- Result: **`0b98ee50-56dc-4c85-9395-d7ac581e82cb`**.
- Accepted Final snapshot: **`92cd0379-c4c2-4f46-bd99-a1505647de72`**.
- Final Analysis phase: **`e2161878-ed60-4ede-bc89-4153b48c9230`**.
- Final Analysis PhaseRun: **`5025ccad-19b1-4498-9a92-10b8face2764`**, Gust run **17**.
- Final tier Gust runs: **14 / 15 / 16**.
- State: **succeeded**. Pilot insufficient; recommended approval rejected; explicit insufficient override accepted.
- Artifact: `local-results/evaluation2-native-study-d826b08c-8b2a-44b9-b927-d4b0a3b38a43.json`.

### Final integrated source execution

This execution repeated the full path after the acceptance-time label guard and Pilot identifier fix.

- Execution: **`be462a1c-c17f-476e-861a-3b86392c7d08`**.
- Result: **`5fc93d33-46c5-45ea-9f09-0c6f15461678`**.
- Accepted Final snapshot: **`1c9f8b55-fe38-4737-8bdb-3976c7db1792`**.
- Final Analysis phase: **`7eb3eff6-a59e-4c68-a759-e24168f8f11d`**.
- Final Analysis PhaseRun: **`19ce1665-94cc-498d-8fa2-f9a8ff7dad29`**, Gust run **24**.
- Final tier Gust runs: **21 / 22 / 23**.
- State: **succeeded**. Pilot insufficient; explicit insufficient override accepted.
- Artifact: `local-results/evaluation2-native-study-be462a1c-c17f-476e-861a-3b86392c7d08.json`.
- Final persisted evidence reread: **20:07:46Z**, in another normal application VM after the owned broker was removed.

Each execution has **18 Pilot items**, **108 Final items**, **108 distinct Final optimization runs**, **108 distinct Final experiments**, **324 completed Final evidence trials**, **six 2×3 comparisons**, **three warm-up batches** and **15 measured receipts**. The two executions share no optimization or experiment IDs. Their scientific matrices and corrected families match exactly. Timing is measured separately and differs.

Both artifacts store every measured triplet. Replica equality was rechecked from persisted observations in the later VM. All comparisons have estimate zero, interval [-8, 8], raw p-value one, adjusted p-value one and no rejection. These small counts do not establish thesis-scale precision, power or calibration. Full statistical calibration remains Goal 06.

## Checks and commands

All owner Mix commands used the disposable environment helper `/tmp/evaluation2-goal05-env.sh`. It loaded `src/.env`, selected localhost port 5433, and read the existing mounted credential files without printing their values. No owner command used the default port-5432 database.

| Exact check, from `src/` | Result / log |
|---|---|
| `MIX_ENV=test EXPECTED_DATABASE=network_defense_test mix run --no-start /tmp/evaluation2-goal05-targets.exs` and corresponding dev check | Both Repo targets verified before owner DB checks; `*-test-targets.log`, `*-dev-targets.log` |
| Read-only Repo startup and development before query | Five original revisions; 9 succeeded / 2 failed Gust runs; no active/queued work; `*-dev-before.log` |
| `MIX_ENV=test timeout 75 mix test test/network_defense/evaluation2/final_analysis_test.exs` | Expected placeholder failures; `*-analysis-red.log` |
| Initial analysis/workflow focused command | Missing Final Workflow path reproduced; `*-workflow-red.log` |
| `MIX_ENV=test timeout 120 mix test test/network_defense/evaluation2 test/mix/tasks/study_command_test.exs test/mix/tasks/study_commands_test.exs` | 350 passed before two final guard regressions; `*-tests.log` |
| Pilot ID command case before fix | Fails because committed ID is absent; `*-command-id-red.log` |
| Acceptance-label case before fix | Fails because changed label still accepts success; `*-acceptance-environment-red.log` |
| Focused analysis/workflow/command rerun after fixes | 26 passed; `*-acceptance-guards-green.log` |
| `timeout 60 mix compile --warnings-as-errors` | Final source exits 0; `*-final-compile.log` |
| `mix format --check-formatted`; `mix credo --strict --format flycheck` | Both exit 0; final precommit also repeats them |
| `MIX_ENV=test timeout 300 mix precommit` | **990 passed, 2 excluded**, exit 0; `*-precommit.log`. Includes all named concern slices plus formatter, frontend type/format checks, strict Credo, Dialyzer, Sobelow and dependency checks. |
| Independent reviewer focused wrapped run | 34 passed; later read-only technical review APPROVE |
| `MIX_ENV=dev REPO_DATABASE=network_defense_dev GUST_ROLE=console EVALUATION_MEASURED_ENVIRONMENT_REVISION=evaluation2-goal05-local timeout 75 mix study.create /tmp/evaluation2-goal05-study.yaml` | Revision created; `*-real-create.log` |
| Same dev target, `GUST_ROLE=core timeout 240 mix study.pilot evaluation2-native-20261031 1` | First Pilot awaits approval; `*-real-pilot.log` |
| `GUST_ROLE=core timeout 60 mix study.final d826b08c-8b2a-44b9-b927-d4b0a3b38a43 --recommended` | Expected invalid_approval, exit 1; `*-real-rejected-approval.log` |
| `GUST_ROLE=core timeout 300 mix study.final d826b08c-8b2a-44b9-b927-d4b0a3b38a43 --override-insufficient tiny` | Succeeded with real effects; `*-real-final.log` |
| `timeout 60 mix study.status`, `study.pilot_result`, `study.result`, `study.continue`, `study.cancel` for the first successful ID | All exit 0 and retain succeeded; `*-real-*-read.log` |
| Separate console VMs for the queued command probe | Reads remain observational, unavailable report/result are bounded, console continuation rejects, cancel leaves zero effects; `*-command-probe-*.log` |
| Final-source `GUST_ROLE=core timeout 120 mix study.pilot evaluation2-native-20261031 1`, then `timeout 300 mix study.final be462a1c-c17f-476e-861a-3b86392c7d08 --override-insufficient tiny` | Second full successful execution; `*-current-source-pilot.log`, `*-current-source-final.log` |
| `GUST_ROLE=console timeout 90 mix run --no-start /tmp/evaluation2-goal05-read-result.exs` | Later-VM result, all timings/equality, effect identities and original graph preservation verified; `*-current-source-durable-read.log` |
| Same read plus `timeout 60 mix study.result be462a1c-c17f-476e-861a-3b86392c7d08` after broker removal | Both exit 0; `*-post-cleanup-evidence.log`, `*-post-cleanup-result.log` |
| Root `git diff --check`; HEAD/reflog inspection | Clean patch whitespace. HEAD `5d132ab` predates goal start. No goal commit. |

Log names above use prefix `/tmp/evaluation2-goal05`. Transient helpers are not a public runner API. The retained definition and real database/artifact identities support a repeat through the ordinary commands.

## Findings and fixes

1. Initial baseline ran while independent workers added their test-first cases. Its failures were the new unimplemented codec/action boundaries. It is not presented as a clean baseline. The later full gate covers the retained predecessor scope.
2. A test fixture reused one study identity while inserting different graphs. The fixture now gives each test revision a unique study ID. Scientific seeds remain independent of that ID.
3. Final Workflow now includes native analysis run parameters, DAG/terminal names, decoding, canonical completion, cancellation stopping and atomic acceptance. The old Goal 04 boundary assertion now expects succeeded.
4. Mapped evaluation output retains comparison positions. The terminal requires its complete succeeded batch to match the succeeded prepare result, including Gust's `gust_task_items` list envelope.
5. Independent review found that Pilot printed its committed execution ID only after continuation. The command now prints the ID before waiting; a red/green regression checks failure ordering.
6. A label-change case exposed missing revalidation immediately before Final acceptance. The capability now rechecks frozen method/seed contracts and label at that boundary. Completed result reads remain independent of measurement configuration.
7. Credo found a complex statistics predicate and test formatting/alias findings. The owner split interval/probability validation and corrected the cases. No finding was suppressed.
8. Dialyzer found an unreachable bare `:error` clause in the Correct action. Its encoder already normalizes failure to `{:error, cause}`. The redundant clause was removed, while Evaluate retains its reachable bare-codec-error handling.
9. Full precommit exposed a concurrent module-definition failure when the topology test loaded its DAG during test-file compilation. The new topology case now loads during serialized `setup_all`. The full gate then passed.
10. Final log scanning found sensitive Repo connection options in existing OTP supervisor shutdown reports from six owned manual probe logs. The owner redacted the exact mounted values and made all owned logs private. No credential value was changed or included in this report. The shared logging path was not redesigned in this goal.

## Preservation deviation and operator resolution

The command worker's first checks used **`postgres@localhost:5432/network_defense_test`**, before the owner supplied the verified port-5433 wrapper. The worker reported that existing DDL lacked its migration metadata. It then performed:

```sql
INSERT INTO schema_migrations (version, inserted_at)
VALUES (20261031131000, now())
ON CONFLICT (version) DO NOTHING;
```

It also ran `MIX_ENV=test mix ecto.migrate`, applying **20261031134500**, `PreserveGraphDeleteCascades`. That migration adds `delete_graph_revisions_before_graph()` and the `graphs_delete_revisions_first` delete trigger. These are the reported changes; they are not an owner-verified baseline comparison.

The owner did not authorize a repair on that target, did not connect to it, and did not attempt a rollback. All later checks used the verified **127.0.0.1:5433** test/development targets. The port-5433 `network_defense_dev` database was not reset or migrated.

After receiving the deviation report and explanation, the operator stated: **“Relax, its dev environment both of them.”** This confirms both targets are development environments and resolves the preservation gate for this milestone. The reported actions remain recorded; this clarification does not establish a missing before-state comparison. No rollback, further port-5432 connection or credential change followed. The independent review remains a technical approval; the environment clarification comes from the operator.

The operator also received the local-log incident report. No further credential action was requested. The six sanitized logs are `current-source-durable-read`, `durable-read`, `command-probe-create`, `command-probe-still-enqueued`, `command-probe-cancelled-proof`, and `post-cleanup-evidence`. All use the prefix above. All 42 owned logs now have mode 0600 and zero exact mounted-credential hits. Credential files and values remain unchanged.

## Changed implementation and cases

- Owner: `lib/network_defense/evaluation2/study.ex`, `study/final/analysis.ex`, `study/workflow.ex`.
- Contracts/DAG/actions: `study/final/analysis_contract.ex`, `study/workflow/final_analysis/actions/{boundary,prepare,evaluate,correct}.ex`, `priv/gust/dags/evaluation2_study_final_analysis.exs`.
- Commands: `lib/mix/study_command.ex` and `lib/mix/tasks/study.{create,pilot,final,continue,status,pilot_result,result,cancel}.ex`.
- Cases: `test/network_defense/evaluation2/final_analysis_{test,workflow_test,contract_test,actions_test,dag_test,load_test}.exs`, `test/mix/tasks/study_{command,commands}_test.exs`, existing `final_workflow_test.exs`, and `test/support/evaluation2_final_fixtures.ex`.
- Documentation: this checkpoint and a narrow README status/evidence update. The separate Goal 05.5 plan and other initial dirty work remain.

## Cleanup and final audit decision

- The exact owned broker **`d1dfa212d63d817467293efc86fb6c0faa8e6183cb1d5dace1821a94f1fce9cb`**, its owned anonymous volume and generated configuration are removed. Shared containers remain.
- Disposable scripts, environment helper and temporary identity/input files are removed. The submitted definition, both result artifacts and the original graph identity baseline remain under `local-results/`. The baseline is `evaluation2-native-study-originals-20261031.json`.
- An extended scan checked ten distinct long secret values from local secret files and sensitive `.env` entries. It found no additional log hits and no hits in the retained result/definition artifacts.
- Normal application result reads still work after broker removal. Final Gust state is **21 succeeded / 3 failed**, with no active/queued work. The extra failed run belongs to the intentional cancelled command probe.
- Two full successful native executions, the command probe and earlier evidence remain durable. No legacy runtime or evidence was retired.
- The owner inspected actual current source, discriminating tests, full regression output, both real artifacts, later-VM reads and cleanup evidence. No required technical path remains unimplemented or unverified in this milestone.
- The operator's confirmation that both database targets are development environments resolves the preservation gate. The final recheck confirms the full technical evidence remains present and the patch is whitespace-clean. **All Goal 05 requirements are achieved, with the reported development-environment deviation retained in the record.** Goal 05.5 is the next milestone; Goal 06 must wait for its documentation refresh.
