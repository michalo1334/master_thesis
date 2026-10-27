# Evaluation rebuild — staged implementation plan

**Workspace handoff:** The authoritative plan and all stage implementation now live in the common worktree at `/home/michalo/master_thesis-evaluation-rebuild`, branch `evaluation/rebuild`. Read `docs/inprogress/evaluation-rebuild-plan.md` there. This original worktree copy predates that handoff; do not use it to select an implementation location.

Status: implementation staging. The lead owns this plan and the high-level design. Each major stage has an interactive `openai/gpt-5.6-sol` implementation agent. The user can direct that agent in its pane.

Read this plan and the [current integration design](evaluation-stage-integration.md) first. The [interview record](grilling-evaluation.md) contains decision history, including rejected proposals; it is not an instruction to implement those proposals.

## 1. Working agreement

- The lead owns intent, architecture, stage boundaries, interfaces, and acceptance review.
- The stage agent owns implementation, relevant tests, formatting, and its handoff.
- The user can correct implementation decisions directly in the stage pane.
- Surface changes to shared architecture or stage interfaces to the lead. Update this plan rather than let stages silently disagree.
- Launch stages in dependency order. Do not run dependent agents against files another stage is replacing.
- Each agent implements only its assigned stage. It does not start the next stage.
- Do not commit, create a worktree, reset branches, or change working location without agreement. Stage 1 can inventory the current tree first, then confirm its implementation location with the user.
- Preserve unrelated working changes. Never use broad restore/clean commands to obtain a clean tree.
- Do not drop user/runtime databases, delete evaluation records, or run live evaluation collections. Isolated test databases and bounded test fixtures are appropriate verification surfaces.

## 2. Standing deletion rule

The working tree must contain only relevant current code.

- Delete obsolete behavior and the tests for that behavior.
- Do not retain disabled tests, skipped legacy suites, unused compatibility adapters, dead routes, old configuration, or commented-out implementations.
- Do not move replaced code into a legacy directory or keep a second inactive implementation.
- Remove obsolete active documentation and setup instructions with the code they describe.
- Git history is the recovery source. Record a baseline reference when useful; do not retain an active backup copy.
- Keep valid scientific regression requirements, but express their tests against the new contracts. ZIP layouts and removed APIs are not regression targets.
- Delete only obsolete material within the approved scope. Shared functionality, scientific data, and unrelated changes are not obsolete merely because a name contains `analysis`.

This rule applies to every stage, not only the initial cleanup.

## 3. Accepted architecture

- One shared Gust study DAG definition, with one run per study execution.
- Specification is input data. Pilot and Final are sections of the same run.
- Save Pilot results before the manual Final-input gate. Continue with a separate Final evidence snapshot.
- Final collection remains manual unless separately approved.
- Gust owns scheduling, progress, retries, and persisted intermediate task results.
- Python is a stateless, compute-only HTTP service. Each request contains its required inputs and returns its completed result.
- Use typed JSON for input snapshots, stage requests, intermediate values, and final results. Save/load JSON in the database.
- No ZIP bundle, archive loading, file manifests/checksums, archive-related CSV conversion, binary report packaging, or archive download path.
- Reuse the existing dashboard where its components remain relevant. Do not create another dashboard application.
- Use ordinary Gust task declarations. Comments explain data flow; no executable data-binding DSL or compiler.
- Use Ecto embedded schemas for Elixir-owned configuration and Pydantic for Python stage contracts.
- The specification composes smaller nested typed structures, serialized together as one JSON document. No separate configuration IDs/tables are required.
- Keep shared comparison and scientific rules in one place. Do not independently copy them into Pilot and Final configuration.
- Confidence, resampling counts, and analysis-seed settings remain owned by selected evaluation inputs. Validate their compatibility and carry them in typed execution inputs.
- Keep configuration separate from selected-run mappings, observation snapshots, lifecycle state, and computed results.
- Retain completed outputs. Retry an interrupted stage with the same effective inputs and seeds. A lost response may cause duplicate computation; exactly-once execution is not promised.
- Internal numerical checkpoints, incompatible-deployment recovery, a Gust fork, and a retained old-executor fleet are out of scope.
- No paid Oban Pro, second Python DAG scheduler, Python job registry, polling/callback protocol, or generic artifact service.

## 4. Major stages

```text
1. Legacy reset
   → 2. Typed contracts and data foundation
   → 3. Stateless Python computation
   → 4. Gust study workflow
   → 5. Dashboard integration and verification
```

### Stage 1 — Legacy reset

**Owner:** Interactive Sol implementation agent.

**Outcome:** Remove the approved legacy analysis setup so the next implementor sees a clear baseline, not competing implementations.

Before deletion:

1. Inventory analysis-specific source, tests, dependencies, infrastructure, routes, scripts, and documentation.
2. Separate these from shared collection/evaluation code, stored data, specification metadata, retained analysis settings, and currently relevant dashboard components.
3. Identify local changes and untracked files that removal would affect.
4. Present a concrete delete/keep manifest to the user in the stage pane. Confirm the implementation location and ambiguous boundaries before editing.

Then remove the approved setup and stale wiring. Remove obsolete tests rather than skip them. Remove old analysis controls if their behavior no longer exists; do not keep fake or disabled implementations to simulate compatibility.

Stage 1 scope clarification after inventory:

- Remove the completed-evaluation ZIP export and its download route too. No independent ZIP-export exception is approved. Keep underlying evaluation data/query logic only where retained collection/dashboard behavior still needs it.
- Keep the current specification validator while the retained editor/save/preview flow uses it. Stage 2 replaces that shape and removes the superseded implementation/tests.
- Keep StudyInputCompatibility only if retained functionality genuinely uses it. If deletion removes all callers, delete the module and its tests. Do not create a placeholder caller to retain it. Preserve the scientific invariants in the design and later current-contract tests.
- The initial agent report is a scope proposal, not completed cleanup. Confirm the implementation location before edits; no runtime source changed during that inventory.

Keep the accepted design and handoff. Preserve the scientific-method reference through Git history, not a legacy source folder.

**Do not:** Build the replacement analysis service, create new specification types, drop database data, or expand cleanup to unrelated features.

**Verification:** Relevant retained application checks pass without the removed setup. No active imports, configuration, routes, or tests require deleted analysis behavior. The handoff identifies intentionally removed functionality and any genuine verification blocker.

### Stage 2 — Typed contracts and data foundation

**Outcome:** Define and implement the small models that all later stages use.

- Nested Ecto specification configuration and its JSON representation.
- Typed evidence/input snapshots, stage inputs, and result shapes.
- Pydantic models for Python stage contracts; no duplicate of the entire Elixir specification.
- Required domain JSON persistence and access. Do not create a generic second store for intermediate values Gust already persists.
- A clear distinction between configured policy, selected evidence, validated analysis settings, and computed output.

Proposed initial configuration groups are PreparationSpec, ComparisonSpec, PilotSpec, and CorrectionSpec. These names/boundaries remain subject to review. Do not create empty types merely to mirror every task.

**Verification:** Serialization and validation checks cover accepted and rejected inputs. Both runtime boundaries agree on the JSON interface. Shared settings have one owner. No archive compatibility or placeholder stage handlers remain.

**Handoff:** Freeze the initial field mapping and request/result contracts before compute and orchestration work depend on them.

### Stage 3 — Stateless Python computation

**Outcome:** Implement numerical stages and synchronous JSON endpoints using the accepted contracts.

Keep numerical functions ordinary and testable. Separate request validation, calculation, and result assembly. Each request supplies all required data; no request depends on an earlier Python request or temporary path.

Preserve scientific behavior:

- Crossed plan/attack sampling and shared attack alignment.
- Existing deterministic seed derivation and canonical comparison ordering.
- The two-dimensional Pilot candidate grid and current recommendation/eligibility rules.
- Candidate outputs are not raw observations for crossed matrices.
- One correction over the complete declared Final primary family.
- The declared comparison reference; no-defense is descriptive, not a substitute for that reference.
- Warm-ups and timing replicas do not become independent outcome evidence.

Use Git history and relevant deterministic scientific fixtures as the baseline. Do not preserve old transport APIs to run old tests unchanged.

**Verification:** Typed request/result tests and bounded numerical checks match the accepted scientific baseline. Repeated effective inputs and seeds produce equivalent scientific results. No server-owned durable state, database client, ZIP handling, or background-job API exists.

### Stage 4 — Gust study workflow

**Outcome:** One durable study workflow coordinates the registered Python stages.

- Integrate Gust through its normal application/configuration and DSL paths.
- Implement individually visible Pilot and Final tasks, including mapped work and complete fan-in.
- Give reused implementations distinct phase-specific task identities; do not create a graph cycle.
- Save completed JSON task results and frozen evidence inputs.
- Implement the manual Final-input gate with durable approval/input state, not browser memory alone.
- Resume Final with separate approved evidence. Do not automatically launch collection.
- Keep shared HTTP transport/result helpers small. Task code supplies inputs and comments explain the connections.

Account for native Gust mapping/result conventions and skipped-prerequisite propagation. Do not assume an unsupported merge or callback guarantee. Escalate a missing capability before adding another scheduler or custom persistence framework.

**Verification:** A mapped stage and join work with stable identities and completeness checks. Interrupted work restarts; completed task outputs are reused. The manual gate and selected inputs survive relevant process/browser restarts. No Python operation lookup is required after an ambiguous response.

### Stage 5 — Dashboard integration and verification

**Outcome:** The existing application presents the new workflow and saved typed results.

- Connect relevant dashboard components to saved JSON, not file parsing.
- Show workflow progress and persisted Pilot results.
- Connect eligibility, manual Final-input submission, and Final result display.
- Remove replaced presenters, adapters, routes, and tests rather than retain compatibility paths.
- Check the full Pilot → gate → Final path and recovery behavior.

**Verification:** Numerical meaning and relevant dashboard behavior match the accepted requirements. No stale archive setup, hidden legacy implementation, or removed-API tests remain. Produce an accurate clean-baseline handoff.

## 5. Stage completion report

Each agent reports:

- Scope implemented and important design decisions.
- Files changed/deleted and unrelated changes left untouched.
- Commands run and their actual results.
- Unresolved blockers and intentionally unavailable behavior.
- Contract/interface details needed by the next stage.

The lead reviews acceptance and updates the stage plan before launching the next implementation agent. A failed check or unresolved partial implementation is not a completed stage.
