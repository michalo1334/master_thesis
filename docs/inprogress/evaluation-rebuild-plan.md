# Evaluation rebuild — current stage

## Status

| Stage | State |
| --- | --- |
| Stage 1 — remove the legacy subsystem | Done. See [the Stage 1 handoff](evaluation-stage-1-handoff.md). Do not restore the subsystem. |
| Stage 2 — one crossed comparison | Implemented, deployed locally, accepted. See [the Stage 2 handoff](evaluation-stage-2-handoff.md). |
| Stage 3 — complete-family Holm correction | Implemented, accepted. See [the Stage 3 design](evaluation-stage-3-design.md). |
| Stage 4 — Precision Pilot | Implemented and committed. The approved local deployment passed a synthetic Pilot check. See [the Stage 4 overview](evaluation-stage-4-overview.md). |
| Stage 5 — Final freeze and approval | No implementation and no approved detailed contract in this branch. Early design material exists outside it. |

The [implemented evaluation pipeline](evaluation-pipeline.md) is the current map of the evaluation software. The tests and deployed checks use synthetic evidence. Scientific settings for a real study remain unapproved, and no study evidence exists.

Do not perform another Terraform apply or any destroy without new explicit approval. Do not define later stages or create a speculative backlog.

**The sections below are the historical Stage 2 brief.** They record the Stage 2 workspace, scope, acceptance criteria, and Terraform apply. Stage 3 ran in the `/home/michalo/master_thesis-stage3` worktree and is merged into `evaluation/rebuild`. Stage 4 ran in the `/home/michalo/master_thesis-stage4` worktree and is committed only on `evaluation/stage-4-implementation`; it is not merged. Do not read the Stage 2 scope as a statement about Stage 3 or Stage 4.

## Shared workspace and ownership (historical Stage 2)

- Worktree: `/home/michalo/master_thesis-evaluation-rebuild`
- Branch: `evaluation/rebuild`
- Implementation baseline: `9a359c5ee7fc48be9642e52d1364508bc4455717`
- Later worktrees: `/home/michalo/master_thesis-stage3` (merged) and `/home/michalo/master_thesis-stage4` (branch `evaluation/stage-4-implementation`, not merged)
- Lead: intent, scientific interpretation, scope, and acceptance.
- Interactive Sol agent: implementation, tests, and checks. The user can direct it in its pane.

Use the worktree for the stage that you are implementing. Do not edit the original `/home/michalo/master_thesis` source worktree. Skills can be read from the original worktree if needed.

## Approved implementation goal

Stage 2 implements this execution path:

```text
Synthetic crossed evidence → native Gust task → Python HTTP computation
    → completed typed JSON → Gust result persistence → read-back
```

Gust owns scheduling and persisted task results. Python owns computation only. Use synthetic evidence, not live evaluation collection or archived data.

## Scientific scope

Implement one primary alternative-versus-CVSS comparison using [the preserved methodology](../concepts/evaluation-methodology.md). That reviewed reference is authoritative for this stage. Historical source paths in that reference refer to Git history, not files to restore.

The calculation returns:

- mean mission-impact difference: alternative minus CVSS;
- the corrected crossed-bootstrap percentile interval;
- the two-sided centered-bootstrap raw p-value; and
- the applicable non-informative or degeneracy status.

Preserve independent plan-row resampling on the two sides and shared attack-column resampling. Do not pair plan rows or flatten trials into independent observations. Express attack-column alignment in the input contract. Reject missing, duplicate, unequal, or incompatible coverage rather than accepting silent misalignment.

Use the documented finite-sample correction, calibrated sample-count lower bounds, and separate interval/null random streams. The historical primary test is a centered bootstrap, not a permutation test. Do not introduce a separate unused permutation-resample setting.

Identical inputs, seeds, and ordering must produce identical statistics. Do not derive scientific randomness from task IDs, retries, workers, or completion order. Any departure from the preserved statistical method requires lead review before implementation.

This prototype does not represent a complete study family. Do not calculate a family-adjusted p-value or present its output as Final study evidence.

## Runtime and contract scope

Use small typed JSON request and response models for this operation. Keep checked-in JSON Schema files as the authoritative wire contracts. Use pinned ExJsonSchema in Elixir, Ecto embedded schemas for typed materialization, and strict Pydantic models in Python. Shared conformance examples must verify both runtime boundaries. Do not generate source from the schemas or build study-wide configuration models, a binding language, or a schema compiler.

The Python request completes synchronously and returns JSON. Python has no database, durable job registry, result lookup service, artifact store, or file-result protocol. A retried request may recompute with the same scientific inputs and seeds.

Use a native Gust DAG/task and native result persistence. Do not replace Gust scheduling or persistence with a parallel mechanism. A client-only test or direct task-body call does not prove the required scheduler/persistence path.

Add only the dependencies, configuration, and migrations needed for this path. Pin the selected Gust dependency and record its actual version or revision. The earlier Gust review is useful research, not proof that another version has the same APIs. Do not fork Gust or add a paid Oban Pro dependency.

Keep graph, simulation, and optimization behavior intact. Those features must not require the Python prototype service to be available.

## Excluded scope for Stage 2 (historical)

- Live evaluation collection, graph/model preparation, or optimizer/topology pilots.
- Study/specification management, precision Pilot, Final collection, or manual-gate workflows. Stage 4 later implemented the Pilot. Stage 5 has no implementation in this branch.
- Complete-family correction, secondary reports, or dashboard/UI work.
- Archive, ZIP, CSV, result-import, or binary download compatibility.
- A general configuration framework, generic operation service, or Python orchestration.
- Production rollout, deployment-version management, or speculative extensibility.
- Restoration of deleted legacy modules, tests, fixtures, commands, or transport contracts.

## Verification and acceptance

The implementation must demonstrate all of the following:

1. A native Gust run executes the task through a real HTTP request to the Python service.
2. The task returns validated JSON and Gust saves the completed result. Read it back and show that it contains the expected scientific output.
3. Repeating the computation with identical inputs, seeds, and ordering gives identical statistics. A saved-result lookup alone is not a recomputation test.
4. Invalid matrix alignment fails explicitly. Invalid evidence must not become a successful stored result.
5. Tests cover the crossed sampling axes, correction/contrast calculation, repeatability, and non-informative/degenerate behavior.
6. Current application tests, compilation, contracts, and relevant formatting/static/build checks pass.

Actually run the real HTTP/Gust demonstration. Do not substitute mocks or a claim that integration should work. Keep a reproducible command or test harness for it. Tests may manage their own temporary service process, but must not stop unrelated services.

Do not add skipped placeholder tests or disabled legacy tests. A separate integration command is acceptable if it is documented and actually passes. Distinguish its results from unit tests.

Project schema/data preservation is not required. Verify the configured database target before any destructive command. Prefer a clearly identified project test/prototype target. Unrelated databases and infrastructure remain outside scope. Do not perform another apply or any destroy without new explicit approval.

## Applied Terraform plan for Stage 2 (historical)

The active local state of the Stage 2 worktree matched all 24 managed Docker containers before apply. The regenerated plan contained exactly nine replacements and 45 no-op resources. The user reviewed that summary and explicitly approved the apply.

Terraform replaced:

- the application development image;
- the application setup container;
- four application containers;
- the evaluation-compute image; and
- two evaluation-compute containers.

Terraform reported `9 added, 0 changed, 9 destroyed`. It changed no database, volume, network, messaging, proxy, or observability resource. All managed services became healthy or completed successfully. A plan after apply reported no changes. Temporary plan, state-copy, checksum, and log artifacts were removed.

## Approved design

The approved design is recorded in [the Stage 2 design](evaluation-stage-2-design.md). It records:

- the user-visible or developer-visible entry point;
- the Gust DAG and task boundaries;
- the canonical request, result, and error schemas;
- library-owned validation, native typed-model, and public error-mapping boundaries;
- evidence identity, ordering, and cross-field validation rules;
- Python service endpoints and lifecycle expectations;
- Gust result-persistence and read-back behavior;
- configuration and secret ownership;
- the minimum demonstration and acceptance evidence.

The implementation follows these choices. Any contract or methodology change still requires lead and user review.

## Handoff and stop condition

The completed Stage 2 outcome is in [the Stage 2 handoff](evaluation-stage-2-handoff.md). It records the implemented request/result path, Gust version, runtime assumptions, deployed demonstration, deterministic persisted results, invalid-input rejection, checks, and exclusions.

The lead retains ownership of the methodology reference and the current-stage brief. Any contract or methodology change still requires lead and user review.

**Do not commit or start another increment without user direction.**
