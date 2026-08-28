# Cloud Evaluation Tooling Plan

## Status

Planned work. Nothing on this page is current behavior. The measured cloud
study is blocked until all four items below exist. The
[runbook prerequisites](cloud-evaluation-runbook.md#prerequisites) and the
[topology-scale cloud protocol](topology-scale-study.md#cloud-protocol) state
this block on the study side.

## Design

The cloud study needs four tooling items. Each item states its purpose, its
dependency order, and its planned output at a high level. Commands, field
names, schemas, and deployment resources are decided when each item is built.

1. **One-off evaluator.** Runs one Mix task inside the deployed environment
   with the application identity, mounted secrets, database access, and
   non-conflicting listeners. Every other item and every study command depends
   on it, so it comes first. Until it exists there is no supported way to run
    the study Mix commands against the deployed environment. The runner
    commands it will wrap are the ones in
    [evaluation lifecycle](../concepts/evaluation.md#resumability-and-runner-commands).
    Its planned output is a safe path to execute an evaluation task in the
    deployed environment.
2. **Topology diagnostic.** Checks that enterprise-generated tiers differ in
   attack-relevant structure before the study freezes them. It records an
   unchanged result when growth leaves that structure unchanged; that record is
   an observed result, not a failure. Depends on the one-off
    evaluator. The [cloud protocol](topology-scale-study.md#cloud-protocol)
    describes the gate it satisfies.
    Its planned output is a diagnostic record for each candidate tier.
3. **Automatic environment record.** Captures the fixed environment record
   from the running environment and compares it with the expected record
   during preflight. Depends on the deployed environment described in
    [architecture](../architecture.md#deployment) and on the image and
    migration work in
    [azure deployment plan, Phase 7](azure-deployment-plan.md#phase-7-build-the-image-and-run-migrations).
    Its planned output is an environment record and its preflight comparison.
4. **Automatic once-per-frozen-manifest warm-up.** A manifest setting that
   requests exactly one automatic warm-up per frozen manifest before measured
   runs. Today warm-up is manual (`mix evaluate.warmup`). Depends on the
    one-off evaluator and builds on the frozen-manifest flow in
    [evaluation lifecycle](../concepts/evaluation.md#resumability-and-runner-commands).
    Its planned output is one automatic warm-up before the first measured run.

## Work order

1. One-off evaluator. Blocks every cloud command.
2. Topology diagnostic. Blocks tier selection and freeze.
3. Automatic environment record. Blocks preflight.
4. Automatic once-per-frozen-manifest warm-up. Blocks the measured-run phase.

## Acceptance conditions

- The one-off evaluator runs a Mix task in the deployed environment without
  host-side credentials, and the runbook can name it as a current command.
- The diagnostic records either a changed or unchanged result for every
  candidate tier. An unchanged result is evidence, not a failure.
- Preflight captures the environment record automatically and reports a match
  or mismatch against the expected record.
- A frozen manifest with the warm-up setting produces exactly one warm-up run
  before its first measured run.
- The runbook and the protocol no longer mark the cloud study as blocked.
