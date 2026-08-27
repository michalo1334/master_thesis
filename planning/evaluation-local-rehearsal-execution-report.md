# Local Evaluation Rehearsal Report

## Result

The local rehearsal completed. It validates the evaluation workflow. It is not
topology-scale study evidence and does not support cloud performance claims.

The source manifests are in `evaluation/scenarios/local-rehearsal-v1/`. The
ignored binary results (archives, analysis outputs, and machine-readable run
summary) in `local-results/rehearsal/` were removed from the local environment
after review.

## Execution

The optimizer pilot used one frozen 20-host graph. It selected 20 optimizer
trials and 5 optimizer iterations. The lower setting changed selected plans.
The selected setting and the higher setting produced the same plans and
mission-impact results.

Each local tier used a frozen graph, one warm-up, and two new complete measured
runs. No measured run used the resume path. Semantic archive comparison passed
for every reference and replica pair. Analysis and pilot outputs exist for every
reference archive.

| Enterprise hosts | Frozen graph revision | Reference / replica evaluator runtime |
| --- | --- | --- |
| 8 | `30fe44eb-61c4-4db0-baca-637f75de436f` | 10,567 / 10,521 ms |
| 12 | `86e562a6-20ae-4163-8ab4-f0233a21bfc4` | 15,109 / 14,883 ms |
| 20 | `67fe8baf-a5e2-4e86-82aa-3d5984148965` | 52,984 / 51,918 ms |

The final 500-trial pilot outputs meet the configured 0.50 half-width target.
This confirms only the local rehearsal configuration. It does not establish a
final cloud trial count.

## Verification

- The local-tier invariant test passed for all three host counts and three
  generator seeds.
- The evaluation manifest contract accepted all source manifests.
- During this execution, `mix precommit` passed: 496 ExUnit tests, static
  checks, and type checks. This session observation has no retained command log.
- The evaluation report component test passed: 10 tests. It renders runtime
  and pre-attack feasibility summaries.
- During this execution, the analysis HTTP service returned one transient `429
  Service busy` response. The saved archives were then analyzed with the
  documented local CLI. This session observation has no retained service log.
- PostgreSQL, both application replicas, and the analysis service were healthy
  after the two pending evaluation-run migrations were applied.
- The Python analysis test suite did not run. `pytest` is absent from the
  analysis dependency groups, and `uv run pytest` uses a system interpreter
  without the package dependencies.

## Report-Only Risks

### Study Design

- Topology segmentation and simulation-informed primary results were identical
  across all three tiers. Random and simulated-annealing results varied at some
  budgets, but not in a coherent scaling pattern. The local tiers validate the
  workflow and observed runtime growth. They do not demonstrate a primary-
  outcome topology-scale relationship.
- Several primary comparisons are degenerate. They have a zero difference and
  a zero-width interval because both compared plans are identical. Such a pass
  does not validate the trial count.
- Mission impact has a coarse discrete scale. The configured 0.50 half-width
  is close to or wider than meaningful outcome steps in this model.
- The reported confidence intervals include simulator uncertainty only. They
  condition on the three declared selection seeds and exclude plan-selection
  uncertainty.
- The optimizer pilot compares only two simulation-backed strategies on one
  graph. It selects a local rehearsal setting. It does not validate optimizer
  settings for the cloud study.
- One frozen graph exists per tier. The rehearsal contains no graph replication
  within a host-count tier.

### Evaluation And UI

- A concurrent attempt to execute the same running evaluation can fail on the
  unique plan constraint. The winner remains valid, but the losing invocation
  can mark its run failed instead of returning an idempotent result.
- Separate runs of the same manifest are semantically equal but not byte-equal.
  Plan identifiers and durations change archive checksums. The comparison tool
  correctly normalizes these fields.
- The report UI shows runtime and feasibility only after final analysis. It
  intentionally does not show them for pilot-only output.
- On narrow screens, the existing report tables require horizontal scrolling.

### Infrastructure

- The local application was initially unhealthy because two tracked migrations
  were pending. The health gate did not make the cause visible until logs were
  inspected.
- Phoenix development mode returned 500 after configuration files changed while
  replicas were running. The server required a restart.
- Host-side Mix lacks the database password. Evaluation required an isolated
  process with the application container's mounted secrets.
- The HTTP analysis service permits one active analysis and can return 429 when
  busy. The CLI avoided this local contention but does not remove it for cloud
  operation.

## Evidence Boundary

Do not cite these measurements as cloud runtime, topology-scale, optimizer
quality, or strategy-effect results. Run a new cloud pilot, freeze new graph
revisions, use five timing replicas, and investigate the invariant primary
outcomes before making those claims.
