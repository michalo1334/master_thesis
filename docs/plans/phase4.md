# Phase 4 Implementation Plan

## Outcome

Comparison stays canonical, derived operational flows have no authoring or persistence path, and active documentation describes the policy model.

## Shared Context

Every implementation and review agent reads `docs/plans/phase4-context.md` before working. It defines the reachability boundary, explored state, and verification commands.

## Chunk 1: Canonical Graph Diff Coverage

Assign `implementor_fast` to add focused backend coverage for policy-edge removal and policy-data changes. Change `GraphDiff` only if a regression test shows that it violates the canonical-only contract.

The tests must show that one removed `SegmentReachability` produces one removed edge diff and no derived operational edge. Add persisted comparison coverage only if it fits the existing LiveView test setup without broad fixture changes.

## Chunk 2: Diff UI And Policy-Link Accessibility

Assign a separate `implementor_fast` to add focused dashboard tests for policy-edge diff rendering and accessibility. The tests must preserve the distinction between editable policy links and read-only operational flows.

## Chunk 3: Boundary Audit

Assign `explorer_fast` to audit all residual reachability paths after the test slices. Remove only a proven authoring, persistence, shortcut, test, or presentation path that violates the boundary. Required in-memory operational support remains.

## Chunk 4: Core Concept Documentation

Assign `implementor_fast` to update `model.md`, `usecases.md`, and `milestones.md`. These documents must describe canonical segment policy, derived operational flows, and policy-boundary defenses.

## Chunk 5: Evaluation And Source Documentation

Assign a separate `implementor_fast` to reconcile `graph-model-evaluation.md`, `credential-privilege-model-plan.md`, and `enterprise-topology-sources.md` with the policy model.

## Chunk 6: Thesis And Historical Drafts

Assign a final `implementor_fast` to update the relevant thesis chapters, mark contradictory initial drafts as superseded, and record Phase 4 completion in `reachability-modeling.md`.

## Review And Verification

After every implementation chunk, assign `explorer_fast` to review the diff against the shared context. Run focused checks after each accepted chunk. Before completion, run the repository boundary audit, `git diff --check`, and `mix precommit` from `src`.
