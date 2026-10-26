# Evaluation architecture

## Status and authority

This page maps the current evaluation runtime for application developers. The public study lifecycle coordinates Pilot and Final collection and analysis. The comparison and family workflows remain reusable lower-level operations. Timing replicas are not implemented.

Only synthetic evidence supports the recorded verification. Real-study settings, evidence collection, and deployment remain unapproved. Historical local checks do not establish current service readiness. See [verification history and limits](../history/evaluation-decisions.md#verification-and-operational-evidence).

| Question                                  | Authority                                                       |
| ----------------------------------------- | --------------------------------------------------------------- |
| Scientific method                         | [Evaluation methodology](../concepts/evaluation-methodology.md) |
| Shared terms                              | [Vocabulary](../concepts/vocabulary.md#evaluation-and-study)    |
| Current behavior                          | Source, checked-in schemas, and tests linked below              |
| Study lifecycle and remaining timing work | [Study pipeline design](../design/evaluation-study-pipeline.md) |
| Decisions and historical evidence         | [Evaluation decisions](../history/evaluation-decisions.md)      |

## Runtime ownership

```mermaid
flowchart LR
    CALLER["Application caller"] --> API["Evaluations lifecycle API"]
    API --> DB[("Application PostgreSQL")]
    API --> COORD["Supervised study coordinator"]
    COORD --> COLLECT["Pilot or Final collection DAG"]
    COLLECT --> DOMAIN["Optimization and simulation APIs"]
    DOMAIN --> DB
    COLLECT --> DB
    COORD --> ANALYZE["Pilot or Final analysis DAG"]
    ANALYZE -->|"bounded synchronous HTTP"| PY["Python numerical compute"]
    PY -->|"typed response"| ANALYZE
    COLLECT --> GS[("Gust PostgreSQL tables")]
    ANALYZE --> GS
    COORD --> DB
    DB --> API
    API --> CALLER
```

This is a data-flow map, not a scheduling DAG.

| Owner                  | Responsibility                                                                                                                         |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Elixir application     | Lifecycle state, strict contracts, collection planning, source binding, coordinator transitions, preflight, and typed result read-back |
| Application PostgreSQL | Immutable study revisions and results; execution, phase, collection, runtime-link, and evidence-snapshot records                       |
| Gust                   | Fixed collection and analysis DAGs, mapped work, retries, run/task state, errors, and saved task results                               |
| Python                 | One synchronous, stateless numerical calculation per request; no database, job registry, scheduler, or result store                    |

The local application and Gust repositories use one PostgreSQL service. Their Ecto repositories, tables, and migration histories remain separate.

Comparison and family requests include bounded matrices in Gust run parameters. Pilot and Final runs instead hold snapshot IDs, settings, positions, and compact results. Do not describe all four workflows as matrix-free in Gust.

## Fixed Gust DAGs

The facade starts the comparison and family workflows. The study coordinator starts the Pilot and Final collection and analysis workflows. No DAG starts another DAG. Family and Final analysis tasks reuse the comparison action and Holm call directly, not nested comparison or family runs.

| DAG                                 | Fixed task shape                                                                     | Output                                          |
| ----------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------- |
| `evaluation_comparison`             | `prepare` → `compare`                                                                | One comparison statistics record                |
| `evaluation_family`                 | `prepare_family` → mapped `compare_member` → `correct_family`                        | One complete-family result with Holm adjustment |
| `evaluation_study_pilot_collection` | `prepare_pilot_collection` → mapped `collect_pilot_item` → `assemble_pilot_snapshot` | One Pilot snapshot ID                           |
| `evaluation_pilot`                  | `prepare_pilot` → mapped `evaluate_candidate_comparison` → `select_pilot`            | One recommendation or explicit insufficiency    |
| `evaluation_study_final_collection` | `prepare_final_collection` → mapped `collect_final_item` → `assemble_final_snapshot` | One Final snapshot ID                           |
| `evaluation_final`                  | `prepare_final` → mapped `compare_final_member` → `correct_final_family`             | One validated Final family result               |

Pilot maps one candidate/comparison pair. Family and Final map one declared comparison. Fan-in restores declared order and rejects missing, duplicate, or unexpected rows. Pilot selects locally and runs no Holm correction. Family and Final apply Holm once across the complete family.

The current Pilot contract uses one ordered candidate list. Each candidate has a stable ID, a plan count per side, and an attack count per plan. The coordinator preserves declared candidate order through analysis and result read-back.

## Public application boundary

[`NetworkDefense.Evaluations`](../../src/lib/network_defense/evaluations.ex) exposes these Elixir operations. They are not public Phoenix routes.

| Capability     | Operations                                                             |
| -------------- | ---------------------------------------------------------------------- |
| Comparison     | `submit_comparison/1`, `await_comparison/2`, `get_comparison_result/1` |
| Family         | `submit_family/1`, `await_family/2`, `get_family_result/1`             |
| Study revision | `create_study_revision/1`                                              |
| Study start    | `start_study/1`                                                        |
| Study status   | `study_status/1`                                                       |
| Study resume   | `resume_study/2`                                                       |
| Study cancel   | `cancel_study/1`                                                       |
| Study result   | `study_result/1`                                                       |

Each comparison or family `submit_*` operation returns a Gust run ID, each `await_*` operation returns the completion status, and each `get_*_result` operation performs a separate, typed read-back from persisted data. All operations return typed success or bounded error values.

The Pilot and Final workflows have no public group. They stay internal to the study coordinator, so a caller cannot start a Gust run, create an evidence snapshot, or read a Pilot or Final result outside one study execution. The Pilot and Final sections below describe those internal boundaries.

The development commands `mix evaluation.compare` and `mix evaluation.family` run named synthetic fixtures. Pilot and Final work runs only inside a study execution.

### Final source and evidence boundary

This is an internal coordinator contract. No caller submits Final work directly.

`resume_study/2` takes only the Final selection: `:recommended` or `{:override_insufficient, candidate_id}`. Every other Final input comes from PostgreSQL. In one locked transaction, the resume command stores the frozen selection, the selected counts, and the override flag, and it creates the empty `final_collection` phase. The coordinator then owns the rest of the boundary:

- it runs Final collection and links the returned snapshot to the `final_collection` phase;
- it reads the accepted Pilot analysis run, the frozen selection, and the Final snapshot when it builds the Final request; and
- it writes the completion assertions from the stored phase rows.

The built request must match the accepted Pilot source and the Final snapshot on:

- study revision and family;
- the complete ordered comparison identities;
- the selected plan count per side and attacks per plan; and
- the declared source and Final metadata.

A recommended Pilot must freeze the recommended counts. An insufficient Pilot accepts only a candidate the stored revision declares, and the stored override flag then records that choice. A failed, invalid, or incomplete Pilot supplies no fallback.

The stored assertions claim that Final evidence was collected after the Pilot and excludes Pilot observations. The contract validates those stored assertions and the completion metadata. It does not authenticate collection history, prove physical freshness, or detect reused observations from matrix values.

Each Final comparison takes its analysis seed from the declared study definition, in declared order. Final does not derive these seeds or compare them with Pilot seeds. Disjoint Pilot/Final collection seeds remain a scientific requirement, not a provenance guarantee from these checks.

## Contracts, limits, and read-back

Checked-in JSON Schemas define the wire shapes. Elixir validates the original values before Ecto materialization, so type coercion cannot hide invalid input. Python uses strict Pydantic models. Shared fixtures and drift tests check agreement.

Submission rejects invalid requests before creating a Gust run. Pilot and Final also load snapshots, check bindings, and preflight every generated compute request. Preflight uses the execution request builder but makes no HTTP call. Preparation repeats the checks against persisted inputs. Mapped tasks validate bounded requests and returned responses.

Snapshot storage size, generated comparison-request size, bootstrap replicates, and total work have separate guards. Each protects a different resource boundary. Pilot also bounds candidate work and outer subsampling. These deployment caps are not scientific settings. Missing or malformed configuration produces bounded errors on the affected paths. No layer truncates evidence, candidates, comparisons, or repeats.

Read-back requires more than a succeeded Gust run:

- Comparison verifies schema and request/result relations, including method, interval, confidence, and test alternative.
- Family verifies membership, order, correction settings, and member relations.
- Pilot reloads evidence and re-derives summaries, pass decisions, and recommendation from the complete candidate rows.
- Final rechecks source/snapshot bindings, order, member relations, and the stored family result.

These checks do not rerun numerical statistics or independently recompute Holm. Schema-valid changes that preserve the checked relations can pass. Read-back is not a cryptographic integrity check.

### Snapshot storage contract

Both roles use `evaluation_evidence_snapshots`. The current table has exactly seven columns:

| Column              | Meaning                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------- |
| `id`                | Snapshot UUID                                                                            |
| `study_revision_id` | Stored study-revision UUID; this snapshot table has no foreign key to the revision table |
| `phase`             | `pilot` or `final`                                                                       |
| `schema_version`    | Snapshot contract version                                                                |
| `family_id`         | Family identifier                                                                        |
| `payload`           | Validated PostgreSQL JSONB document                                                      |
| `inserted_at`       | Insertion time                                                                           |

Create paths encode the normalized payload with [`JsonBoundary`](../../src/lib/network_defense/evaluation/json_boundary.ex). They enforce the configured encoded-size cap immediately before insertion. They do not store a byte-count column.

Read paths validate the stored contract, metadata, relations, and non-byte limits. They do not re-encode the payload or perform a read-time byte check. There is no `payload_bytes`, `updated_at`, content hash, or database immutability trigger. Create/read-only access is an application rule. Changed evidence needs a new snapshot ID.

### Compute HTTP boundary

| Internal route                                     | Operation                                    |
| -------------------------------------------------- | -------------------------------------------- |
| `POST /v1/comparisons/corrected-crossed-bootstrap` | One crossed comparison; also reused by Final |
| `POST /v1/families/holm`                           | One complete-family correction               |
| `POST /v1/pilots/candidate-comparisons`            | One Pilot candidate comparison               |
| `GET /health`, `GET /ready`                        | Liveness and readiness                       |

The calculation routes return `400` for invalid JSON, `413` for oversized bodies, `415` for unsupported media types, and `422` for validation failures. Documented `500` and `503` envelopes describe calculation or temporary service failures. See the [shared error contract](../../src/priv/evaluation/contracts/v1/schemas/error.schema.json) and [`ErrorEnvelope`](../../src/lib/network_defense/evaluation/error_envelope.ex). Diagnostics are bounded and exclude submitted values and stack traces.

## Ordering, randomness, and retries

Scientific identity is `(tier, budget, alternative, reference, outcome)`. Arrays define comparison and candidate order. Object key order, database row order, and completion order do not.

Pilot preserves the historical tier/occurrence offsets and candidate-specific child streams. Separate streams serve outer sampling, interval draws, and centered null draws. The [methodology](../concepts/evaluation-methodology.md#10-reproducibility-and-limits) explains the scientific constraints. The [Pilot implementation](../../services/evaluation_compute/src/evaluation_compute/pilot.py) and tests define the exact stream contract.

Temporary transport failures and valid documented HTTP `500`/`503` failures remain retryable. Documented client errors, malformed success responses, and contract mismatches are permanent. Invalid response envelopes do not become retryable merely because the HTTP status is `500` or `503`.

A retry retains the request and scientific seeds. Work can execute more than once after a lost response. The coordinator accepts one Gust run for each phase in one execution, but another study execution creates new runs. There is no exactly-once computation guarantee. The prototype adds no automatic coordinator restart recovery or phase replay.

## Source ownership

| Concern                              | Authoritative location                                                                                                                                                                                                        |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Comparison and family                | [`comparison/`](../../src/lib/network_defense/evaluation/comparison/), [`family/`](../../src/lib/network_defense/evaluation/family/)                                                                                          |
| Study lifecycle and collection       | [`study/`](../../src/lib/network_defense/evaluation/study/), [`study_execution.ex`](../../src/lib/network_defense/evaluation/study_execution.ex), [`study_phase.ex`](../../src/lib/network_defense/evaluation/study_phase.ex) |
| Pilot and Final analysis             | [`pilot/`](../../src/lib/network_defense/evaluation/pilot/), [`final/`](../../src/lib/network_defense/evaluation/final/)                                                                                                      |
| Snapshots                            | [`evidence_snapshot.ex`](../../src/lib/network_defense/evaluation/evidence_snapshot.ex), [`evidence_snapshots.ex`](../../src/lib/network_defense/evaluation/evidence_snapshots.ex)                                            |
| DAGs                                 | [`priv/gust/dags/`](../../src/priv/gust/dags/)                                                                                                                                                                                |
| Schemas and conformance fixtures     | [`priv/evaluation/`](../../src/priv/evaluation/), shared through [`contracts/evaluation/`](../../contracts/evaluation/)                                                                                                       |
| Compute routes and numerical methods | [`evaluation_compute/`](../../services/evaluation_compute/src/evaluation_compute/)                                                                                                                                            |
| Verification                         | [`Elixir evaluation tests`](../../src/test/network_defense/evaluation/), [`Python tests`](../../services/evaluation_compute/tests/)                                                                                           |

## Remaining boundary

The current runtime has the YAML boundary, immutable normalized study revisions, the study state machine, fixed collection and analysis DAGs, explicit resume and cancellation, and one immutable compact result after success.

T1+T2 are next. They add the replica schedule and elapsed intervals. T3+T4 later add environment checks, equivalence checks, and canonical replica selection. T5 then adds timing summaries and the manual timed journey. The [study pipeline design](../design/evaluation-study-pipeline.md) defines that work.

This prototype does not authorize deployment, real evidence collection, automatic restart recovery, phase replay, or production scientific settings.
