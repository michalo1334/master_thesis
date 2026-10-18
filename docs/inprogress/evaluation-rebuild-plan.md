# Evaluation rebuild — current stage

## Status

**The Stage 2 design is approved and the bounded prototype is implemented.** Focused tests, the full repository precommit suite, Docker build, and Terraform validation pass. Independent scientific, Elixir/Gust, and infrastructure reviews report no blockers.

Stage 1 removed the legacy evaluation subsystem. Its cleanup and verification remain recorded in [the Stage 1 handoff](evaluation-stage-1-handoff.md). Do not restore that subsystem.

The current gate is the Terraform plan review. Do not apply or destroy infrastructure until the user reviews the plan and gives separate explicit approval. Do not define later stages or create a speculative backlog.

## Shared workspace and ownership

- Worktree: `/home/michalo/master_thesis-evaluation-rebuild`
- Branch: `evaluation/rebuild`
- Implementation baseline: `9a359c5ee7fc48be9642e52d1364508bc4455717`
- Lead: intent, scientific interpretation, scope, and acceptance.
- Interactive Sol agent: implementation, tests, and checks. The user can direct it in its pane.

Use this existing worktree. Do not create another worktree or edit the original `/home/michalo/master_thesis` source worktree. Skills can be read from the original worktree if needed.

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

## Excluded scope

- Live evaluation collection, graph/model preparation, or optimizer/topology pilots.
- Study/specification management, precision Pilot, Final collection, or manual-gate workflows.
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

Project schema/data preservation is not required. Verify the configured database target before any destructive command. Prefer a clearly identified project test/prototype target. Unrelated databases and infrastructure remain outside scope. Do not apply or destroy infrastructure.

## Reviewed Terraform plan

A read-only plan against a temporary copy of the existing local state succeeded. It reported 26 additions, no in-place changes, and two deletions:

- create the evaluation-compute image and one container for each of the two sites;
- replace the local application development image;
- create the application, database, messaging, proxy, and observability containers that are currently absent;
- delete the removed legacy analysis image; and
- delete no Docker volumes.

The original state checksum did not change. The temporary state and plan files were deleted after review. The active local state still resides in the original worktree. Before an approved apply, choose an explicit state-location procedure and regenerate the plan against that state. Do not apply a copied or stale state.

This plan contains destructive actions for the application image and the legacy analysis image. It is not approved for apply by its creation or review.

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

## Future implementation handoff and stop condition

Write `docs/inprogress/evaluation-stage-2-handoff.md` with:

- the implemented request/result path and current source locations;
- the exact Gust version/revision and relevant runtime assumptions;
- the commands and actual results for the real demonstration and checks;
- evidence of persisted-result read-back, deterministic recomputation, and invalid-input rejection;
- any limitation or unresolved blocker.

Describe the result, not a later-stage plan. If a library limitation or scientific ambiguity blocks the path, report the evidence and ask the lead. Do not silently fork a dependency, change the method, or expand scope.

The lead retains ownership of the methodology reference and this current-stage brief. The implementation agent must not concurrently rewrite them. Report any required change to the lead.

**Do not commit.** Stop after this prototype and its verification for lead/user review.
