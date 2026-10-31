# Native Evaluation2 verification record

This page preserves the native implementation's verification summary independently of temporary delivery plans.
It records observations from 2026-10-31, rather than current service health or scientific findings.
The [operator guide](../evaluation2.md), [methodology](../concepts/evaluation-methodology.md)
and [architecture](../architecture/evaluation-architecture.md) define current usage.

## Verified implementation scope

| Area | Recorded evidence |
|---|---|
| Constructor | Real YAML construction, graph/Host resolution, policy and bounds checks, typed persistence/reload and seed invariants |
| Numerical core | Independent sequential anchors, matching-cover checks, predictable betting, interval inversion, Decimal Holm and Pilot subset cases |
| Pilot | Real service-backed collection/analysis, complete report, explicit approval boundary and separate-VM cancellation |
| Final collection | Sequential small/medium/large tiers, excluded warm-up, five measured replicas, durable timing, scientific equality and accepted representative evidence |
| Native Final | Accepted-snapshot binding, complete corrected family, atomic result/success and public result reads |
| Commands | Create, Pilot, Final approval, continue, status, Pilot report, result and non-dispatching cancellation |
| Regression | Final native implementation checkpoint: `mix precommit` exited zero with 990 tests passed and two opt-in cases excluded |

The regression checkpoint included compile, formatter, frontend checks/build, strict Credo, Dialyzer, Sobelow, dependency checks and tests.
It retained one pre-existing ignored external Gust type warning.
These results describe that checkpoint, rather than every future source revision.
Current behavior cases live in [`src/test/network_defense/evaluation2/`](../../src/test/network_defense/evaluation2/).

## Two real local executions

Both executions used the retained RabbitMQ executor and real optimization/simulation effects.
They ran the normal application against local development.
The second repeated the full path after the acceptance-time environment guard and Pilot execution-ID reporting fix.
Its durable evidence was read again at `2026-10-31T20:07:46Z` in another application VM after the owned verification broker was removed.

| Setting or observation | Recorded value per execution |
|---|---|
| Master seed | 20261031 |
| Frozen method contract | `crossed-matching-betting-v1` |
| Seed contract | `evaluation2-sha256-json-v1` |
| Family alpha / interval confidence | 0.05 / 0.95 |
| Tiers | Small, medium, large |
| Alternatives / reference | Random and simulation-informed versus shared CVSS |
| Budgets | One action in each tier |
| Counts | Two plans per side, three attacks per plan |
| Pilot outcome | Insufficient |
| Final approval | Explicit insufficient override for a declared candidate |
| Pilot items | 18 |
| Final items and effects | 108 items, 108 distinct optimization runs, 108 distinct experiments |
| Completed Final evidence trials | 324, including warm-up and all measured replicas |
| Comparisons | Six, each with aligned 2×3 matrices |
| Replica protocol | Three warm-up batches and fifteen measured receipts |
| State | Succeeded with a durable owning result |

The small/medium/large graphs had 16/51/101 Hosts, 53/135/260 total nodes, and 71/201/404 edges.
Each graph's frozen mission-impact range was `[0,8]`.
The two executions shared no physical optimization or experiment identities and reproduced the same scientific matrices/family.
Their elapsed timings differed.

All six estimates were zero, intervals were `[-8,8]`, raw/adjusted p-values were one, and no null was rejected.
The assessments were numerically informative with no warnings.
This combination demonstrates why an informative assessment does not imply useful precision.
Both overrides gave up the Pilot precision target.
These runs establish the protocol at small counts, rather than power or empirical calibration.

### Local evidence artifacts

The original detailed artifacts remain local and can be absent from another checkout.
They contain the historical execution/result/phase/effect identities; guides use no live identity as an input default.

- Submitted definition: `local-results/evaluation2-native-study-definition-20261031.yaml`.
- First result: `local-results/evaluation2-native-study-d826b08c-8b2a-44b9-b927-d4b0a3b38a43.json`.
- Integrated-source result: `local-results/evaluation2-native-study-be462a1c-c17f-476e-861a-3b86392c7d08.json`.

The definition artifact is evidence from its original database, rather than a portable example.
Use the [identity-free template](../examples/evaluation2-study.yaml) for new work.

## Timing and failure evidence

The measured protocol uses plan start, a shared plan-completion/simulation-start boundary, and replica end.
Each durable receipt satisfies `total = plan selection + simulation`.
Completed receipts reconstructed all fifteen timing triplets after the original caller and clock owner were gone.
A real mid-measurement clock-loss check failed the incomplete tier without replacement work or invented timing.
Measured-replica equality retained scientific meaning and excluded generated IDs and durations.

Separate-command checks showed that status/report/result inspection left an unrelated queued native run unclaimed with zero effects.
Console cancellation committed terminal application state and fenced that queued run, still with zero effects.
Late completions and finite API timeout cases remained covered by retained behavior tests.

## Preserved failures and limits

Earlier failed numerical, binding, acceptance, command and clock checks led to corrections before the successful checkpoint.
The [method decision record](evaluation2-statistical-validation.md) retains the rejected bootstrap's null counterexamples and the conditional native derivation.
The [legacy decisions](evaluation-decisions.md) retain earlier architectural choices as history.
Neither record is a compatibility contract.

A helper used the default port-5432 test target before the intended target verification.
The original report disclosed that deviation and lacked a baseline comparison for that operation.
The operator confirmed that both targets were development environments, resolving the preservation question.
Later owner checks explicitly verified both Repos at the intended local port-5433 test/development targets.
No later database reset or rollback followed that clarification.

The original probe logs contained credential values in OTP supervisor reports.
The owner redacted those values, restricted all 42 owned logs to mode 0600, and found zero exact-value hits on rescan.
This history does not imply credential rotation or authorization for further infrastructure changes.

Full prespecified calibration remains pending.
The [statistical protocol](evaluation2-statistical-checks.md) defines its models, counts and assessment criteria.
Legacy implementation/schema/service deletion also remains pending until that verification gate passes.
Deletion requires a repeated documentation, example and link audit.

## Documentation checks

The documentation refresh checks the identity-free YAML through `Study.create_revision/1` with sandbox graphs.
Both Repos used the verified local `network_defense_test` target, with SQL Sandbox and the existing file-secret configuration.
No development reset or new service-backed study was needed.

| Check | Observed result |
|---|---|
| `mix test test/network_defense/evaluation2/documentation_example_test.exs` | Four passed: expanded real construction, unexpanded-token rejection, foreign-Host rejection and unknown-key removal |
| `mix precommit` | Exit zero; 994 passed, two opt-in broker cases excluded; retained source/frontend/static gates passed |
| `mix compile --warnings-as-errors` | Exit zero after the module-documentation edits |
| Compiled `Code.fetch_docs/1` audit | 27 public/major/task modules and 80 selected operations have prose; seven native Mermaid sources remain in compiled docs |
| Runtime AST comparison against the source checkpoint | All 18 edited library/task files differ only in documentation attributes or comments |
| Local Markdown navigation audit | 47 files, 296 relative links, zero missing files/anchors; all three referenced PNGs exist |
| Lifecycle diagram comparison | Both current lifecycle diagrams match all 14 actual transitions with no extra edge |
| C4 relationship check | Every endpoint is declared in the context/container sources; relationships also checked against runtime ownership |
| Retained execution artifact audit | Both records have the documented counts, disjoint physical effects, matching scientific evidence/family and fifteen consistent durable/public timings |
| `mix help study.*` | All eight supported task help pages are available |
| Preservation and secret checks | Earlier immutable evidence and three PNGs retain their bytes; no exact secret-file value appears in scanned guides/owned logs |

The example checks dispatch no scientific work and preserve execution/optimization/experiment counts.
Full precommit includes expected failure-fixture logs and emitted unused-alias/dynamically-loaded-DAG warnings during tests; its result is successful.
Initial documentation compilation found duplicate `@doc` attributes; the owner removed the duplicates before the passing checks.
The compiled-doc audit also found two undocumented Persistence operations; the owner documented them and reran the audit.

Earlier historical links to removed documents now appear as labeled former paths, rather than broken navigation.
Lasting guides depend on this stable record and the stable method/protocol records rather than temporary execution files.
The method-decision and prespecified-protocol bodies preserve their original scientific content unchanged.
A final read-only review corrected the environment-check sequence, zero-estimate p-value wording, polling description and setup-alias instruction.
The three existing PNGs illustrate the graph/simulation/optimization UI and contain no evaluation interface; the refresh leaves them unchanged.
No committed rendered native diagram output existed to regenerate.

There is no ExDoc dependency or `mix docs` task in the project; `mix help docs` reports the missing task.
Neither `mmdc` nor a Mermaid package is installed, and no diagram-render configuration exists.
The refresh adds no documentation platform or renderer dependencies.
Diagram checks establish source-to-code agreement and declared relationships, rather than Mermaid parser or visual-layout validity.
Rendered ExDoc HTML and Mermaid SVG/PNG remain unverified. No rendered-output claim follows from these source checks.
