# Evaluation2 consolidated refactor scope

## Status

**Consolidated scope and completed-delivery reference.** The native constructor, numerical core, Pilot, Final collection, Final analysis and commands reached the verified full-study milestone. The [stable verification record](../history/evaluation2-verification.md) preserves that evidence independently of temporary delivery files. The complete [prespecified calibration](../history/evaluation2-calibration-20261031.md) passed its declared model-grid checks. The obsolete implementation and authorized local remnants are removed; the stable verification record lists retained-tree evidence. Q141 selects the matching-based method in [statistical validation](evaluation2-statistical-validation.md); Q140 permits isolated local testing. The recorded delivery uses dependency-ordered, three-hour batches with substantive owner implementation.

This file defines the complete end state and constraints. Individual goals define intermediate milestones; a completed intermediate goal is not completion of the whole refactor.

## 1. Outcome and completion evidence

Once authorized, complete the new Evaluation2 subsystem so that a real study can follow:

```text
new YAML
  → frozen revision
  → Pilot collection and analysis
  → Pilot report / awaiting_final
  → explicit operator approval
  → sequential Final tiers, each with warm-up and five measured replicas
  → statistically justified native Final analysis and family correction
  → durable result / succeeded
```

Complete means:

- The reviewed methodology is implemented and its assumptions are documented.
- Behavior-focused unit and integration cases pass.
- The real local-development study completes with actual optimization/simulation effects, not mocked effects presented as end-to-end evidence.
- Timing/evidence/identity invariants and the important re-entry/cancellation cases pass.
- Code and tests pass independent review against the agreed design and test plan.
- Legacy analysis/Python retirement is complete and the retained application compiles and works.

A compile, mocked journey, or old-output match alone is not completion.

## 2. Authoritative inputs and precedence

Read these current documents:

1. [Refactor sketches](evaluation2-refactor-sketches.md).
2. [Behavior and statistical test plan](evaluation2-test-plan.md).
3. [Statistical validation and method gate](evaluation2-statistical-validation.md).
4. [Prespecified statistical checks](evaluation2-statistical-checks.md).
5. [Coordination decisions](grilling-evaluation2-gust-coordination.md), especially Q114 onward and Q81/Q97–Q113 references.
6. `.pi/tmp/evaluation2-prototype-review-policy.md`.
7. The existing implementation and relevant scientific-method documentation.

Latest user decisions override older scaffold assumptions. In particular:

- Q141 selects matching-based bounded-mean betting for fixed-sample inference, with pointwise intervals and valid marginal p-values under the declared IID-input model. Native results may differ from Python.
- New format only; no old-definition readers, migration adapters, or compatibility suites.
- Permanent behavior tests are now required. Earlier exclusions are superseded.
- Q140 explicitly permits local `network_defense_test` in the existing PostgreSQL instance. Verify both Repo targets before setup; preserve development for the real study and perform no additional development reset.
- The full local development reset has already completed; do not repeat it as routine cleanup.
- Dependency-ordered goal batches, each limited to three total elapsed hours. Each implementing owner starts 1–2 disjoint scaffolding workers, implements the main logic itself, and performs integration/checks. The final review/deletion gates remain mandatory.

Historical code and documents are references, not a reason to preserve a defect.

## 3. Boundaries

### Retain

- `NetworkDefense.Evaluation2` as the subsystem namespace and `Study` as its supported facade.
- Existing graph, optimization, simulation, compute/RabbitMQ APIs and infrastructure.
- Existing Persistence ownership, transaction, effect-reservation, and canonical identity mechanisms where they remain correct under the new model.
- One Elixir module per source file.
- Existing optimization strategy vocabulary and registries; do not create a duplicate strategy enum.

### Avoid

- Direct Evaluation2 dependencies on `NetworkDefense.Evaluation` legacy modules.
- A background study coordinator, stored Final tier cursor, generic workflow registry, new statistics-engine framework, or remote CLI attachment/RPC mode.
- Domain timing or lifecycle logic in Mix tasks.
- Raw monotonic readings in durable evidence.
- Per-strategy world-model, action-permission, or feasibility overrides in the initial format.
- Production-hardening projects, a custom test platform, blanket coverage quotas, or test-only production abstractions.
- Commits, unrelated worktree edits, credential changes, Terraform apply, or remote/production database writes without an explicit request.

The worktree contains pre-existing changes. Preserve unrelated changes and user artifacts.

## 4. Definition and input

Implement the minimal new input schema and one supported constructor path:

```elixir
Study.create_revision(yaml)
# => {:ok, %Study.Revision{study_id: ..., revision: ...}}
# or a bounded Study.Error
```

The shape is specified in the sketches. Complete it rather than porting the old definition tree mechanically:

- Study identity, one seed, one family alpha, one shared defense policy, one shared simulation model.
- Fixed small/medium/large tier slots, each with frozen graph/Host input, explicit budget list, and ordered alternatives.
- CVSS reference is implicit; no independently configured reference budget or action policy.
- Each scored strategy declares objective and scoring trial count; its world model is inherited.
- Candidate count pairs and non-negative extra pool capacity.
- One shared analysis confidence level for the intervals Pilot plans and Final reports, separate from family alpha. Pilot precision declares outer count, target half interval span, and guard quantile. Remove bootstrap counts, duplicate confidence fields, and the empty Final input block.

Use the existing YAML and JSON Schema libraries. Ignore extra keys and drop them during construction. Keep required known fields strict. Do not add a general schema/validation framework.

Resolve graph existence and foothold membership/type once before freezing. Use direct persisted graph inputs in this first format, not parallel compatibility selector forms. The validation study can populate a disposable YAML document from seeded graph APIs.

Construct independent facts once. Derive capacity, comparison membership, group order, scalar seeds, and effective policy. Reject remaining irreducible domain contradictions before starting effects. Do not repeat creation-owned validation in each downstream task.

Persist and reload the new typed Definition with Spectral metadata intact. Update all current Evaluation2 consumers rather than projecting the new input back into the old independently editable model.

## 5. Physical collection and evidence

Use unique physical strategy groups for each tier/budget context, including CVSS once. Comparisons project alternative/reference groups.

```text
group A rows ──────→ A versus CVSS
CVSS rows ─────┬───→ A versus CVSS
              └───→ B versus CVSS
group B rows ──────→ B versus CVSS
```

- One physical row owns one CollectionItem and its unique optimization/experiment links.
- Do not link a single effect into multiple CollectionItem rows.
- Retrying an item reuses its reserved effects.
- Another replica or phase creates fresh effects, even when scientific inputs match.
- The immutable plan stores resolved requests. Tasks load those requests instead of reconstructing mutable work.
- Comparison order: tier order, budget declaration order, alternative declaration order.
- Group order: tier order, budget order, CVSS followed by alternatives.
- Definition-global group positions and phase-run-local item positions are different coordinate spaces.

The collection SQL table shapes can remain. Change the typed WorkItem/plan and evidence projection to represent groups directly. Numerical code receives scientific matrix views, not persistence records.

Preserve trial identity and common attack-column alignment. Existing simulation trial indices are one-based; do not change their seed policy accidentally.

## 6. Randomness and numerical method

Implement only the matching-based bounded-mean method selected in Q141. Use the exact recipe and caveats in statistical validation and section 6 of the sketches; do not port the failed bootstrap.

Required properties:

- Population estimand and random sampling units are explicit, conditional on frozen graphs/model settings.
- Row/column dependence matches the actual collection design and algorithms.
- Empirical zero spread does not become unsupported population certainty.
- Raw p-values/intervals have a stated justification and supported regime.
- Holm claims are conditional on valid marginal inference; between-comparison dependence is permitted.
- Pilot precision is presented honestly as a heuristic or validated planning procedure, according to the selected method.
- Fresh Final data and the frozen family/procedure remain independent of Pilot selection.
- Outcome units and any bounds come from the graph model, not observed sample minima/maxima.

Use Nx float64 and Decimal where needed. Add CPU EXLA only for an observed performance need. Keep backend choice internal.

The sketches contain an explicit root encoding and allocation rule to verify against library behavior. Row inputs include optimizer/scoring randomness; attack inputs remain separate. Pilot candidates use shared outcome-independent permutation prefixes. Final comparison is deterministic and needs no resampling seed. Retain one source seed and derivation identity, with actual resolved seeds in plan/effect records. No scientific seed may depend on database IDs, task completion order, process identity, or timing-replica position.

Do not port NumPy RNG compatibility. Native repeatability and the recorded new contract matter; old numerical equality does not.

## 7. Workflow and Gust

Complete four Evaluation2-owned static DAGs:

- Pilot Collection.
- Pilot Analysis.
- Reusable Final Tier Collection.
- Final Analysis.

Keep the approved create-link-dispatch order. Preallocate the PhaseRun UUID, bind it into Gust input, link the canonical row, and dispatch only the linked winner. Serialize conditional dispatch through the authoritative Gust run row while status remains created. Clean up only a known undispatched losing run; no general orphan scanner or Gust fork.

Implement the existing phase-contract codecs and completion proof. Require canonical run/input binding, succeeded run status, one succeeded terminal task, and typed output. Analysis also binds the accepted snapshot. Do not accept an arbitrary successful run from another phase or tier.

Public behavior:

```elixir
Study.start(revision)
Study.resume(execution_id, approval)
# ensure first durable run and return Status

Study.continue(execution_id)
Study.continue(execution_id, timeout: milliseconds)
# block to approval/terminal boundary, or return current Status on timeout
```

Persistence creates successor phases and owns all transitions. Final tier progression derives from ordered canonical PhaseRuns; store no cursor. Apply the internal capability map in section 4 of the sketches. Reuse Collection for Pilot/shared work, add no symmetry-only Pilot.Collection facade, and replace placeholder phase-wide runners that duplicate Workflow. Final Collection prepares evidence; it does not own lifecycle acceptance. Keep Study/report reads through typed completion access and Views without a cycle back from phase policy into orchestration.

RunMonitor is a wait-only singleton. It may observe application cancellation while waiting, including cancellation from another command VM. Do not rely exclusively on local messages. Gust has succeeded/failed terminal run statuses; application cancellation is separate.

Typed permanent task failures remain permanent. Unexpected exceptions use Gust retry behavior. Map definitive failure to the active application phase through existing ownership/witness contracts. Do not mask programming errors behind exhaustive exception containment.

## 8. Final timing and acceptance

Timing belongs inside the domain capability, not Mix tasks. The application supervises the clock service before new work can be dispatched.

Each tier executes warm-up and measured replicas 0..4 with the same scientific inputs and fresh effects. The domain clock receives explicit plan/simulation boundaries. Gust timing-task results persist completed replica durations.

Use a clock-session token bound to the tier. A restarted clock must reject an old incomplete session. Completed timings remain readable without the old owner. Release transient clock state only after durable completion proof; do not make cleanup erase needed retry receipts.

After all tiers finish, Workflow proves canonical completion and decodes the typed results. Final Collection checks durable durations and measured-replica equality, then assembles representative evidence and prepares the snapshot through Persistence. Snapshot presence alone is not acceptance. Workflow requests `Persistence.Executions.accept_final_collection/1`; its locked transition/successor is the durable witness. Rebuild timing summaries from completed tier receipts after caller loss. Final analysis acceptance stores its corrected family and timings through the existing transaction owner.

Exclude physical execution/output artifact IDs, timestamps, clock sessions, and durations from equality. Retain meaningful frozen input identity, logical action targets, settings, seeds, and scientific outcomes. Warm-up is excluded from measured evidence and summaries.

Unequal or interrupted measured work fails; no silent replacement replicas.

## 9. Provenance

Remove ten mandatory operator revision assertions from YAML. Keep graph/work/effect/Gust identities with existing owners.

- Frozen definition metadata records method/seed contracts and expected configured environment label.
- Execution records available application/runtime/dependency facts in one small owned JSON field if required.
- Missing optional repository metadata is explicit unavailability, not an invented identity or a normal-path blocker.
- Final boundaries reread the configured label and reject missing/changed measurement configuration.

Do not present a label as authenticated hardware/software identity. Do not add a manifest-history or environment-fingerprinting framework. Re-entry must not mix known incompatible numerical/seed contracts or builds.

## 10. Commands

Implement the proposed thin command surface in the sketches, with explicit revision creation, Pilot execution, Final approval, continuation, status/report/result, and cancellation.

- Commands start the normal application; no attachment/RPC mode.
- Execution commands need execution-capable Gust.
- Read-only inspection must not start unrelated queued work; use the existing non-executing startup role where appropriate.
- Mix owns argument handling, startup, bounded error presentation, and result formatting only.
- Final approval is explicit; no interactive prompt or implicit approval.
- Execution commands wait indefinitely to their boundary. API wait timeout returns Status without cancellation; whole-VM exit still stops workers/clocks and can invalidate incomplete measurements.
- Cancellation commits application state before best-effort stopping.

Investigate the existing setup/migration sequencing failure and apply the smallest justified fix. Verify application and Gust migration order before seeding. Do not infer the cause solely from the original symptom.

## 11. Testing, review, and evidence

Implement the concern-based cases in [the test plan](evaluation2-test-plan.md). Test observable behavior, not private helper calls, SQL text, migration counts, incidental formatting, or old numerical output snapshots.

Use test-first development for changed behavior. Keep fixtures small and reusable. Use an independent test author within the batch if delegation is available; otherwise report the limitation and retain independent test-implementation review.

The approved automated-integration target is local `network_defense_test` in the existing PostgreSQL instance. Use existing SQL sandbox conventions where compatible with Gust integration. Verify host/port, credentials, name, and both Repo targets before creating it or running setup. The development database is local `network_defense_dev` at `127.0.0.1:5433`; its reset and seeding already completed. Do not reset it again as routine cleanup.

Manual full-study evidence must use real retained optimization/simulation services. Record whether Pilot recommended a candidate or Final used an explicit insufficient override. Do not convert a failed/insufficient result into a fake success to satisfy the demonstration.

Statistical validation must follow predeclared assessment criteria and report assumptions, counts, seeds, Monte Carlo uncertainty, and limitations. A seeded toy unit test is not a coverage or family-error proof.

Use a representative native workload profile to assess practical performance. No fragile machine-speed assertions in fast tests.

### Documentation milestone and deletion recheck

Goal 05.5 updates current guides, ExDoc, examples, diagrams and navigation after the verified native study. Check actual code and accepted contracts; flag material divergence rather than document it as intended. Validate example construction and the worked command flow safely, distinguish history from current guidance, and keep unrun calibration claims explicitly pending. Goal 06 reruns this audit after deletion and removes references to deleted artifacts. Preserve verified evidence and avoid a new documentation stack.

## 12. MUST DELETE the retired subsystem

Only after the native path and scientific checks pass, MUST DELETE the following. The obsolete implementation must be absent from the active project as if it never existed:

- Legacy facade and analysis/pipeline source, obsolete comparison/family Mix tasks, DAG sources, and application registrations.
- Python evaluation_compute source and service-only configuration.
- Local Terraform evaluation_compute module and wiring; validate source but do not apply infrastructure changes without permission.
- Obsolete legacy schemas, fixtures, and tests serving only retired modules.
- All stale in-scope legacy DAG definitions through existing Gust APIs, without deleting native evidence or resetting development.
- Dead superseded scaffolds and project-local retired build/cache artifacts. No disabled copy, archive directory, compatibility wrapper, alias, empty stub, Python fallback, or deferred-removal TODO may remain.

Preserve the new input schema and ex_json_schema dependency. Preserve the measured-environment label configuration. Preserve graph, optimization, simulation, compute/RabbitMQ infrastructure and unrelated tests/dependencies. The retirement audit found no legacy web/API/frontend route that requires replacement UI.

Rebuild and rerun relevant tests and native result reads after deletion. Require a zero-leftover file/reference/dependency/DAG audit of the active implementation, tests, config, build and deployment source. Historical decisions/citations may mention the past; they preserve no runtime path. Protected data or unauthorized operations block completion rather than justify leftover implementation. Remove no unrelated user results, secrets, worktree changes, or infrastructure resources.

## 13. Internal order and stop conditions

Use one implementing owner per goal and follow the dependency order in the goal plan. Each owner must implement substantive logic after its initial scaffolding fan-out:

```text
behavior cases and definition/model
  → collection-group adaptation and native method
  → complete Pilot/continuation
  → Final timing/collection
  → Final analysis/result
  → commands and setup correction
  → full verification
  → retirement
  → final regression/review fixes
```

Fix the highest-priority supported-path or scientific defect first. Rerun affected cases after each correction and the agreed regression set before reporting completion. Do not spend iterations on speculative hardening or unrequested abstractions.

If the method cannot be justified, calibration fails, required services are unavailable, or safe local targets cannot be established, stop with evidence, attempted paths, the exact blocker, and the next input needed. Do not substitute mocks, skipped checks, or unavailable infrastructure for completed end-to-end evidence.

## 14. Final report

Report:

- Implemented scope and main source paths.
- Selected statistical method, assumptions, supported regime, and any changes from the baseline.
- Cases/tests run, results, and important failures or skips.
- Statistical/calibration evidence and performance observations.
- Manual full-study commands and execution/result identity, with credentials omitted.
- Retirement/configuration changes and retained infrastructure.
- Independent review outcome and remaining material blockers.

No commit unless the user requests one.
