# Evaluation decisions

This record preserves durable choices and historical evidence from the evaluation rebuild. It replaces the stage plans, handoffs, remediation notes, Gust review, and design discussion. It is not an implementation plan.

Read the [runtime map](../architecture/evaluation-architecture.md), [target lifecycle](../design/evaluation-study-pipeline.md), and [methodology](../concepts/evaluation-methodology.md) for current authority.

## Accepted decisions

- Remove the legacy evaluation subsystem rather than keep compatibility paths. Git history preserves its source, not deleted database rows. Retain graph, simulation, optimization, and their independent UI behavior.
- Preserve the alternative-minus-CVSS estimand, independent plan rows, shared attack columns, corrected crossed bootstrap, centered null bootstrap, and complete-family Holm method.
- Use strict checked-in JSON Schemas, typed Elixir materialization, and strict Python models. Shared conformance fixtures check both runtimes. Do not allow coercion to hide invalid wire types.
- Keep two mutually exclusive bounded error forms: domain/operational `issues` and native validator `schema_errors`. HTTP, persisted Gust failures, and terminal output must support both. Exclude submitted values, exception data, and stack traces.
- Require explicit compute-service startup settings and blocking deployment validation. Image rebuild triggers track effective build inputs, not unrelated workspace files.
- Let Gust own fixed phase execution and persisted task results. Python is synchronous, stateless, and compute-only. A repeated pure calculation is acceptable.
- Store Pilot and Final matrices in application-owned PostgreSQL JSONB snapshots. Keep their Gust work items and results compact. Snapshot access is create/read only at the application boundary.
- Enforce snapshot encoded-size caps on create through `JsonBoundary`. The current seven-column schema has no stored byte count. Reads validate contracts and relations, not encoded-byte equality or content integrity.
- Keep scientific settings and deployment caps separate. Oversized work fails; no layer silently truncates evidence or repeat counts.
- Preserve declared order and historical Pilot streams. Retries, workers, task IDs, and completion order must not change scientific randomness.
- The pre-lifecycle direct Final boundary required a valid recommended Pilot, exact selected counts, and a separate Final snapshot. The active lifecycle supersedes that public boundary. Its coordinator now reloads the frozen selection, accepted Pilot phase, and Final snapshot from PostgreSQL.
- Use YAML input, an immutable normalized definition, one application state machine, and fixed phase DAGs. Do not store source YAML.
- Use one supervised ephemeral coordinator task between phases. Persist one row for each fixed phase and its Gust run. Gust completion callbacks are non-authoritative wake-up signals only. Do not add an Oban lifecycle worker, automatic restart recovery, or phase replay.
- Use separate Pilot and Final collection DAGs with shared actions. Gust maps coarse collection work; the simulation API retains ScatterGather trial execution.
- Always pause after valid Pilot analysis. Permit explicit confirmatory resume after insufficiency only with one declared candidate. Expose `pilot_override`; store no override actor, reason, or special timestamp. This is limited audit evidence, not a claim of adequate precision.
- Make repeated Gust task effects safe through stable collection items. Do not claim exactly-once task execution.

The insufficient-Pilot exception changes the earlier no-fallback policy for the study lifecycle only. `resume_study/2` records the declared override candidate and `pilot_override`. Its [scientific risks](../concepts/evaluation-methodology.md#insufficient-pilot-confirmatory-override) remain explicit.

## Rejected or superseded designs

| Design                                                                                     | Accepted replacement                                                            |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| Archive/ZIP interchange, file manifests, and a Python artifact store                       | Typed JSON responses, application evidence snapshots, and compact results       |
| Separate Python DAG scheduler, GustPy execution, or durable remote-operation registry      | Gust schedules fixed tasks; Python computes one bounded request                 |
| Runic as an additional scheduler or paid Oban Pro                                          | Native Gust phase execution without a second scheduler                          |
| Data-binding DSL, source generation, dynamic DAG topology, or a generic workflow framework | Ordered input data and checked-in fixed DAGs                                    |
| One shared lifecycle DAG with a provisional stage catalog                                  | Application lifecycle state machine and separate phase runs                     |
| YAML or JSON as alternative user input formats                                             | YAML-only transport; normalized JSON-compatible persistence                     |
| Calibration phase and separate approval/declaration subsystem                              | Declared immutable inputs and an explicit pause/resume gate                     |
| Automatic largest-candidate fallback                                                       | Manual selection of one declared candidate after an insufficient Pilot          |
| Hashes or signed manifests merely for identity                                             | Database IDs, immutable revisions, and explicit software/environment references |

Internal numerical checkpoints, bitwise replay across changed environments, and production cross-deployment recovery were deferred. Existing dashboard concepts do not imply an implemented evaluation UI.

## Verification and operational evidence

These are historical results, not checks rerun during this documentation consolidation. Synthetic results establish software paths only, not study findings.

| Milestone                    | Recorded evidence                                                                                                                                                                                                                                                                                                                                        |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Legacy removal               | Fresh test-schema migration removed legacy evaluation ownership. The retained application passed 417 Elixir tests with two exclusions and 575 frontend tests. Graph, simulation, and optimization remained.                                                                                                                                              |
| Crossed-comparison prototype | A real Gust/HTTP/persistence/read-back path passed. Two deployed runs returned identical statistics; invalid attack-column alignment created no run. The handoff recorded 47 Python tests and 464 Elixir tests with two exclusions.                                                                                                                      |
| Contract remediation         | Strict parsing, bounded native schema diagnostics, safe serialization, response classification, startup validation, and Terraform blocking validation passed focused and full checks. The record reported 47 Python tests and 457 Elixir tests with two exclusions. These runs used different revisions; counts are not cumulative.                      |
| Local comparison deployment  | An approved Terraform apply replaced nine application/compute resources. It changed no database, volume, network, messaging, proxy, or observability resource. A subsequent plan reported no changes.                                                                                                                                                    |
| Complete-family component    | Commit `887d282` added the family workflow and one complete-family Holm operation. Automated coverage includes mapped failures, retries, order restoration, persisted validation, and coordinator restart.                                                                                                                                               |
| Precision Pilot              | Commit `fefe324` added the Pilot. A local check on 2026-10-19 verified repeatability, explicit zero-impact insufficiency, matrix-free Pilot Gust records, preflight rejection, and separate application/compute cap rejection. Comparison and family checks stayed valid. The record reported 127 Python tests and 650 Elixir tests with two exclusions. |
| Final analysis component     | Merged commit `082330e` added Final snapshots, source binding, public Final operations, schemas, conformance fixtures, and Gust integration tests. It also removed stored snapshot byte counts. No real-study collection or deployed Final study result is established.                                                                                  |

The remediation handoff recorded a replacement plan, not an apply. The later approved deployment record establishes the separate apply. Do not infer infrastructure changes from a successful plan or build.

The last operational record states that application, compute, messaging, and observability services stopped after authorized cleanup. PostgreSQL, pgAdmin, their volumes, and local networks remained. This is not a current health check. Further apply or destroy operations require separate approval.

## Known limits and risks

- The pre-lifecycle direct Final APIs checked assertions, not physical collection provenance. The active lifecycle adds authoritative revision, phase, and source binding, but it still does not authenticate physical collection history. A relation-preserving matrix change can pass stored-contract checks. No hash or database trigger protects snapshot immutability.
- Insufficient-Pilot override accepts unmet precision, potentially wide intervals, unstable raw p-values, and post-Pilot selection bias. Holm does not repair weak evidence.
- Gust `0.1.40` can re-arm retry budgets after coordinator restart. A lost response or effect-before-completion window can repeat work.
- The Gust source review found no task-effect fence from the run lease. Stable collection items must prevent duplicate optimization, experiment, and snapshot effects during task retry.
- The ephemeral coordinator does not reconnect after an application restart. An active execution can remain stuck until the operator cancels it and starts a new execution.
- Gust run persistence does not preserve an immutable executable DAG or imported Python environment. Cross-deployment recovery remains outside the prototype.
- The historical Pilot deployment did not undergo active-run fault injection/restarts, parallel-run load, or near-limit valid capacity checks. Family automated restart coverage is not deployed Pilot proof.
- Native ExJsonSchema diagnostic paths do not escape slash and tilde as typed JSON Pointer paths. They remain diagnostic text. Bounded adapters exclude submitted values and exception traces.
- Historical checks reported a Starlette/AnyIO deprecation warning and asset chunk-size warnings. They did not fail those checks.
- The original Gust source review noted inconsistent license metadata. That review alone did not resolve the package-license question.
- Synthetic lifecycle and collector verification exists. Real-study values, representative resource capacities, evidence collection, and deployment remain unapproved. No real-study or deployment verification exists.

The Gust assessment examined [core source at `23fc836`](https://github.com/marciok/gust/tree/23fc8361482c2f85169c89a384d3a5ee73c2f317) and [GustPy at `e40bbc0`](https://github.com/marciok/gust_py/tree/e40bbc00295d2eb50ea1e4ab5652cb3d5533da15). It was a source review, not a crash-test result. The [evaluation methodology](../concepts/evaluation-methodology.md) states the scientific protocol independently of that software review.
