# Goal 01 — Foundation

## Outcome and clock

- Start UTC: **2026-10-31T12:55:46Z**.
- Deadline UTC: **2026-10-31T15:55:46Z** (start + 10,800 seconds).
- Reserved verification window: no later than 15:40:46Z. Work finished early; final checks ran before that window.
- Final audit UTC: **2026-10-31T13:53:04Z**. Elapsed time at audit: 57 minutes, 18 seconds.
- Reporting finished UTC: **2026-10-31T13:56:40Z**. Total elapsed: 1 hour, 54 seconds.
- Status: **verified complete for the foundation milestone**.
- Goal 02 did not start. Native inference, Pilot analysis/continuation, Final execution, calibration, the real full study, and retirement remain later milestones.

## Assignments and ownership

| Helper | Assignment | Outcome |
|---|---|---|
| `foundation-scout` / scout | Read-only inspection of existing collection, effects, persistence, setup, and tests | Reported current boundaries and paths; made no changes |
| `foundation-types` / worker / `deepseek/deepseek-flash` | Nested types and minimal schema scaffolding | Delivered typed declarations and schema; owner corrected external field names and tier shape to the approved YAML contract |
| `foundation-tests` / worker / `deepseek/deepseek-flash` | Independent fixtures, behavior cases, test bootstrap | Delivered parser/derivation/seed/revision cases; owner integrated the database boundary and corrected fixture assumptions |
| `foundation-review` / reviewer, with two follow-ups | Independent source and assertion review | Final verdict: **APPROVE**; no current-slice blockers |

The owner implemented construction, graph resolution, policies, bounds, seed allocation, derived views, consumer changes, grouped planning/evidence, request binding, setup fixes, and collection/Gust checks. Workers did not delegate recursively. All helpers shared the original deadline. No owned background work remains.

## Prompt-to-artifact audit

Paths below are relative to `src/`, except the checkpoint and design documents.

| Requirement | Current artifact and direct evidence |
|---|---|
| Read the goal and governing contracts | `AGENTS.md`, goal README, refactor sketches, consolidated brief, behavior plan, statistical validation/checks, coordination decisions, and prototype review policy informed construction and review. This goal follows the six-milestone plan. |
| Record the original clock; preserve it across continuation | Start/deadline above were written before implementation. Continuation retained the same deadline. Commands used finite timeouts below the remaining allowance. |
| Fan out to 1–2 scaffold workers using the requested model; retain substantive owner work | Assignments above. Both implementation scaffold workers used `deepseek/deepseek-flash`. |
| Accept the new YAML/schema; require known fields and strict primitives; drop extras | `priv/evaluation2/definition.schema.json`, `study/definition/schema.ex`, `Definition.parse/1`, `Study.create_revision/1`; INPUT-01 acceptance/rejection/projection cases. Tier input uses the three named slots, and alternatives use `strategy`. |
| Construct independent typed facts; avoid compatibility readers and duplicated editable declarations | `Definition` and its nested types store source seed, shared settings, tiers, candidates/extras, precision, and captured provenance. Tests check dropped legacy/extra fields and derived-only membership/capacity. |
| Persist and reload trusted Spectral values | `Persistence.insert_revision/1` and `fetch_revision/1` retain their Spectral owner. Revision tests check nested typed equality through derived views, provenance, graph/Host identities, and immutable identity conflicts (INPUT-02/03). |
| Resolve graph/Host membership before insertion | `Definition.resolve/1`; missing graph, foreign Host, non-Host, required infeasibility, and unusable topology setup all fail before revision insertion. |
| Freeze finite model bounds | Constructor sums positive capability weights from resolved graphs. NUM-06 cases verify a controlled sum of 9, reject overflow, preserve structural zero, and show independence from seed/alpha and observations. Evidence checks finite observations against those frozen bounds. |
| Apply one shared policy and model | `effective_action_types/2`, `require_feasibility?/1`, `Collection.WorkItem` request builders; POLICY-01 tests check CVSS's patch intersection, simple/scored variants, inherited rules/horizon/attempts, and persisted scoring/evidence feasibility. |
| Stable bounded seed allocation | `study/randomness.ex`; exact compact-JSON/SHA-256 anchors from an independent Python calculation, phase/role/row separation, declaration-order stability, and allocation checks cover RNG-01/02. Attack trials retain the existing one-based `Simulation.Seed.child_seed/2` policy. |
| Derive capacity, comparisons, and unique groups | `pilot_capacity/1`, `comparisons/1`, `collection_groups/1`; MODEL-01 checks 30×60 capacity, nine ordered comparisons, 14 groups, canonical positions, and shared CVSS references for the independent fixture. |
| Collect unique physical groups; retain separate coordinate spaces | Pilot work stores definition-global group position and logical row position. SQL item positions remain local to each phase-run plan. COL-01 verifies physical row count/order, immutable plan reload, and repeated preparation. |
| Preserve retry effect links | COL-02 executes actual optimization and simulation twice and checks unchanged canonical links. Existing reservation locks and transaction owners remain in `Persistence.Collection`. |
| Fresh effects for another replica or phase; repeat scientific inputs | COL-03 executes fresh replica and execution/phase items. Their effect IDs differ; the scientific requests and seeds remain equal. No effect link is shared between items. |
| Assemble complete, correctly bound matrices and shared CVSS projections | COL-04 executes real effects and checks ordered rectangular matrices, shared reference projections, model bounds, and one-based attack columns. Corrupt optimization seeds, experiment settings, or trial seeds fail assembly. Incomplete effects create no snapshot. |
| Preserve the Pilot completion boundary | `gust_collection_test.exs` starts through `Study`, runs the actual Pilot DAG with Gust workers, and reads a succeeded canonical run, terminal receipt, and evidence. It checks nine unique physical effects for six comparisons. Completion-proof tests reject wrong input and failed/missing terminal tasks. Study state remains `collecting_pilot`; acceptance belongs to Goal 03. |
| Adapt existing consumers without claiming later analysis | `Pilot.Analysis.prepare/1` derives jobs and stable comparison streams. `Persistence.Executions` reads new candidate counts; `Views` derives comparison identities and fixed Holm metadata. Analysis/evaluation/report placeholders remain visibly unavailable. |
| Diagnose migration-before-seeding failure; apply a small fix | The old alias invoked `ecto.migrate` twice. Mix executed that task once, so Gust tables stayed absent. `mix.exs` now invokes one migration task with both Repo flags. Fresh setup logs show application migrations, then Gust migrations, then seeding. |
| Verify safe application/Gust setup and seeded graph usability | Final fresh test setup and the seeded smoke below pass. The smoke constructs/reloads a revision from 15/50/100-host seeded graphs, checks both running applications, and rolls back its revision. The separate Gust test exercises actual dispatch and effects. |
| Preserve shared domains and implemented behavior | Fresh setup exposed missing effect-setting columns and a pre-existing graph-delete cascade failure. Two additive migrations supply the current effect fields and order graph revision deletion before identity cascades. Full regression, immediate membership checks, snapshot immutability, and direct identity protection pass. No graph/optimization/simulation/compute source was replaced. |
| Preserve development, credentials, and dirty work; avoid forbidden operations | All database writes used verified local `network_defense_test`. Development's five graph revision identities retain the hash below. No credentials changed, development reset/migration, commit, Terraform apply, remote write, compatibility reader, or legacy/Python deletion occurred. Existing unrelated dirty files remain outside this change. |

## Checks and exact commands

Commands ran from `/home/michalo/master_thesis/src`. Database commands used the existing local secret file; its value was never printed or changed:

```sh
set -a
. ./.env
set +a
export REPO_PASSWORD_FILE=/home/michalo/master_thesis/infra/environments/local/secrets/postgres-password
```

Before setup, the owner inspected both resolved Repo configurations with `MIX_ENV=test mix run --no-start --no-compile`. Both reported user `postgres`, host `localhost`, port `5433`, database `network_defense_test`, and a present password. Gust uses `gust_schema_migrations`; both use SQL Sandbox. Docker port inspection confirmed the local PostgreSQL binding. A direct connection confirmed the test target.

| Command | Final result | Evidence |
|---|---|---|
| `timeout 90 mix compile` | Exit 0 | Full application compiles |
| `timeout 90 mix credo --strict --format flycheck` | Exit 0; no findings | `/tmp/evaluation2-credo-final.log` |
| `mix format --check-formatted` on changed Elixir files | Exit 0 | Checked application, nested types, migrations, support, and tests |
| `git diff --check -- src/lib/network_defense/evaluation2 src/mix.exs` (repository root) | Exit 0 | No patch whitespace errors in changed tracked source |
| `MIX_ENV=test timeout 150 mix test test/network_defense/evaluation2` | **132 passed**, exit 0 | `/tmp/evaluation2-foundation-tests-final.log` |
| `MIX_ENV=test timeout 180 mix test` | **770 passed, 2 excluded**, exit 0 | `/tmp/evaluation2-regression-final.log`; the existing default excludes RabbitMQ-tagged cases |
| `MIX_ENV=test timeout 120 mix test test/network_defense/evaluation2/setup_test.exs test/network_defense/graph/graph_test.exs` | **17 passed**, exit 0 | `/tmp/evaluation2-setup-regression.log` |
| `MIX_ENV=test timeout 40 mix ecto.drop` followed by `MIX_ENV=test timeout 150 mix ecto.setup` | Exit 0 on the isolated test target | `/tmp/evaluation2-setup-final.log`; both application migrations, all Gust migrations, and five seed graphs precede application checks |
| `MIX_ENV=test timeout 90 mix run /tmp/evaluation2-foundation-seeded-smoke.exs` | Exit 0 | `/tmp/evaluation2-seeded-smoke.log` |

The seeded smoke reported: both applications started; three resolved tiers; each frozen range `[0,8]`; nine comparisons; 14 groups; capacity 30 plans × 60 attacks. Its temporary revision was rolled back. The disposable script was removed after verification; the result log remains.

The actual Gust collection smoke used the normal application with a test-local executor and explicitly started Gust dispatch. It ran real optimization and simulation implementations. It does not claim a RabbitMQ deployment check or a complete scientific study.

## Diagnoses and review fixes

1. **Local connection:** `.env` contained a stale password. The existing mounted local secret worked. No credential file changed.
2. **Old test schema:** `network_defense_test` already existed with old partial migrations and zero graphs, nodes, optimization runs, experiments, and Gust runs. The owner saved `/tmp/evaluation2-test-before-setup.dump` before rebuilding this authorized isolated target. Development was untouched.
3. **Gust migration omission:** two calls to the same Mix migration task in one alias caused the second call to be skipped. The old setup returned success while `gust_dags` was absent. One call with both Repo flags fixes setup and the test alias. Fresh setup verified real table availability and seed construction, rather than relying on alias text.
4. **Effect settings absent from SQL:** reservation failed because `optimization_runs.execution_config` did not exist. Experiments also lacked `rules` and `require_pre_attack_feasibility`. The additive migration supplies these existing domain fields. Historical rows are not assigned invented settings.
5. **Graph cascade order:** full regression failed on the original restrictive snapshot identity FK. A `BEFORE DELETE` graph trigger now removes its revisions before existing identity cascades run. Immediate cross-graph checks and snapshot protections remain intact. Experimental NO ACTION/deferred constraint variants were rolled back on test and are absent from the final source.
6. **Independent review:** fixed the captured environment key to `:measured_environment_revision`; added persisted non-nil-label coverage. Added creation-time feasibility/topology checks and pre-insertion failures. Rebuilt model fixtures before graph insertion to respect immutable snapshots. Added independent seed anchors. Final review approved the source, test assertions, real Gust check, and cascade fix.
7. **Evidence binding:** assembly now compares immutable optimization inputs/configuration and experiment settings, in addition to graph/root/column identities. Mutation regressions first failed, then passed after the checks were added.

## Changed files

Main owner files:

- `src/lib/network_defense/evaluation2/study.ex`
- `src/lib/network_defense/evaluation2/study/definition.ex`
- `src/lib/network_defense/evaluation2/study/randomness.ex`
- `src/lib/network_defense/evaluation2/study/collection.ex`
- `src/lib/network_defense/evaluation2/study/collection/work_item.ex`
- `src/lib/network_defense/evaluation2/study/persistence/collection.ex`
- `src/lib/network_defense/evaluation2/study/persistence/executions.ex`
- `src/lib/network_defense/evaluation2/study/pilot/analysis.ex`
- `src/lib/network_defense/evaluation2/study/views.ex`
- `src/mix.exs` (targeted edits over its pre-existing changes)

Nested definition types/schema under `src/lib/network_defense/evaluation2/study/definition/`:
`candidate.ex`, `comparison.ex`, `defense.ex`, `family.ex`, `graph.ex`, `inference.ex`, `pilot.ex`, `precision.ex`, `provenance.ex`, `sample_size.ex`, `schema.ex`, `scoring.ex`, `simulation.ex`, `strategy.ex`, `study.ex`.

Other new source:

- `src/priv/evaluation2/definition.schema.json`
- `src/priv/repo/migrations/20261031131000_persist_shared_effect_settings.exs`
- `src/priv/repo/migrations/20261031134500_preserve_graph_delete_cascades.exs`

Tests under `src/test/network_defense/evaluation2/`:
`collection_test.exs`, `definition_parse_test.exs`, `definition_rejections_test.exs`, `derived_views_test.exs`, `gust_collection_test.exs`, `randomness_test.exs`, `revision_creation_test.exs`, `setup_test.exs`.

Support: `src/test/support/evaluation2_foundation_fixtures.ex` and `src/test/support/evaluation2_graph_fixtures.ex`.

Documentation: this checkpoint and the goal README status. No unrelated pre-existing documentation or agent changes were reverted.

## Safety and next milestone

A read-only development query over ordered `(revision id, graph id, revision number)` rows returned the same five revisions before and after final checks. SHA-256:

```text
8c01c7f700699e514cb298b66c4a6100082b39d42276bb8b1bbf20f932a6eba0
```

The new migrations were applied only to test. Apply normal additive migrations before a later real development study; do not reset development. Native numerical implementation and its named NUM/HOLM cases belong to Goal 02. No calibration, Final result, or retirement completion is claimed here.

Review noted a future ownership concern: frozen JSON graph references do not themselves prevent an explicit graph deletion before effects exist. No supported deletion path made this a foundation blocker. Preserve that concern when adding a graph-deletion interface.

**Audit result:** every Goal 01 deliverable has source and execution evidence. No required foundation work remains.
