# Evaluation2 redesign — overview and approved structure

> Design-interview history. Later decisions can supersede earlier proposals and example interfaces.
> Use the [native operator guide](../evaluation2.md), [current architecture](../architecture/evaluation-architecture.md) and [stable verification record](../history/evaluation2-verification.md) for implemented behavior and status.

> Part of the [Evaluation2 redesign index](grilling-evaluation-redesign.md).

## Status

Working design interview for the new Evaluation2 study subsystem. Reuse the established methodology, YAML study definition, scenarios, comparisons, strategies, and supporting code. Adjust existing contracts where the simpler Evaluation2 design needs it.

**Implementation framing:** Create Evaluation2 as a new subsystem. Do not describe this work as a refactor of the legacy Evaluation subsystem. Treat legacy source as a library of proven mechanisms and calculations that Evaluation2 can copy or reuse selectively. Evaluation2 must not depend on modules in the legacy `NetworkDefense.Evaluation` namespace.

**Agreed interview scope:** Reuse the existing evaluation approaches. Create simpler code and mechanisms that make them work.

Preserve the methodology, current YAML, domain concepts, and scientific flow as the baseline. Interview decisions should focus on unnecessary implementation layers, repeated checks, orchestration, handoffs, and supporting code. Propose input or interface adjustments only when a concrete simplification requires them.

Study means the existing YAML input, reused and tweaked as needed. Source exploration should answer questions about existing concepts before the interview introduces design choices.

The study pipeline and its Gust phase DAGs are the current design focus. Treat proposed application modules as placeholders. Assume they do not exist yet.

Gust already owns mapped batches, dependency fan-in, and task retry. Do not duplicate these features in application code.

Use existing source as a mechanism library. Reuse or copy the current lifecycle, phase sequencing, explicit resume policy, stable effect links, Final tier DAG, timing rules, and scientific calculations.

Design order: define the phase DAGs and the application boundaries between them. Then assign placeholder actions, inputs, outputs, and persistence.

**User correction:** The initial Pilot/Final diagram was already too detailed for the bird's-eye view.

### Interview mode

The user asked the assistant to continue without waiting for an answer at every step.

- Inspect existing code before asking factual questions.
- Keep established approaches as the baseline.
- Refine one implementation responsibility at a time.
- Prefer module trees, function signatures, data shapes, and short code sketches.
- Introduce each design question with a concrete worked example and explain its effect before asking.
- Keep prose short outside the worked example and decision rationale.
- Keep behavior cases. Defer automated test design.
- Record implementation recommendations as proposals, separate from confirmed requirements.
- Ask when a remaining choice needs user input.

## Decision tree

Leaves summarize questions and answers. `Open` marks an unresolved decision. The interview follows one branch at a time.

```mermaid
mindmap
  root((Evaluation2 creation))
    Purpose
      Scope: complete study Q1
      Interface: Mix tasks
      Reporting scope: deferred Q2
    Study
      Meaning: YAML input Q4
      Format: reuse and tweak
      Check ownership: proposed Q6
      Start boundary: superseded by Q57
      Definition ownership: Evaluation2-owned Q63
      Internal grouping policy: Result aggregate Q64
      Persistence organization: Study context plus Persistence Q65
      Use-case orchestration: Study context Q66
      Internal capability namespaces Q67
      Phase contract ownership Q68
      Physical file policy: one module per file Q69
      Cross-cutting ownership: direct Study modules Q70
      Collection capability: one internal module Q71
      Target module map: frozen Q72
    Method
      Method baseline: predefined Q3
    Workflow
      Pilot approval: explicit
      Gust phase DAGs: reuse batching Q7
      Sequential tiers: application lifecycle
      Lifecycle: reuse current
      Final tier receipt: empty Output Q25
      Final handoff record: reconstruct Q26
      Phase root inputs: phase-run based Q39
      Pilot collection output: empty receipt Q40
      Pilot analysis API: internal Q41
      Supported facade: Study Q42
      Public return types: boundary views Q43
      Revision identity: declared pair Q44
      Pilot result access: separate read Q45
      Status view: state union Q46
      Pilot outcome type: outcome union Q47
      Approval and selection: intent versus frozen Q48
      Result view: six fields Q49
      Result family envelope: Holm singleton Q50
      Timing measurements: replica-position maps Q51/Q62
      Comparison result types: typed nested values Q52
      Pilot result shape: detailed assessments Q53
      Comparison identity: shared Study value Q54
      Tier and strategy types: split ownership Q55
      Public error type: one issue list Q56
      Create and start boundary: separate operations Q57
      Final analysis API: one internal service Q58
      Pilot terminal detail: complete summaries Q59
      Collection contract names: macro-generated Q60
      Phase dispatch typing: typed wrappers Q61
      Timing operations: public queries Q62
    Data
      Persistence shape: resolved by Q12-Q37
      Evidence handling: resolved by Q18-Q20 and Q36-Q37
      Pilot outcome reason: omit Q11
      Frozen selection shape: nested Selection Q12
      Override flag: derive Q13
      Selection persistence: map Q14
      Pilot outcome duplication: single owner Q15
      Gust run ownership: unified StudyPhaseRun Q16
      StudyPhase role: minimal grouping Q17
      Snapshot ownership: collection phase Q18
      Evidence role tag: derive Q19
      Evidence identity copies: definition-owned Q20
      Phase-run status: Gust-owned Q21
      Result history copies: Final-only Q22
      Timing summaries: derive Q23
      Timing tier keys: tier-keyed map Q24
      Collection item owner: phase run Q27
      Work position copies: item-owned Q28
      Planned work storage: one phase-run plan Q29
      Plan item content: resolved requests Q30
      Work identity copies: Evaluation2-owned Q31
      Collection plan API: prepare-and-persist Q32
      Collection item API: complete replica batch Q33
      Effect reservation API: item ID only Q34
      Collection execution API: split effect stages Q35
      Evidence assembly API: phase-derived Q36
      Evidence value type: retained Q37
      Pilot terminal output: nested outcome Q38
    Reuse
      Existing approaches: baseline
    Documentation
      Terminology glossary: open follow-up
    Behavior cases
      Check policy: proposed Q10
```

## Approved structures

The structural design is frozen through Q57. Evaluation2 is a new subsystem. The diagrams show the target structures, not the current scaffold.

### Supported Study API

```mermaid
classDiagram
    direction LR

    class StudyFacade {
        <<facade>>
        +create_revision(yaml) Revision
        +start(revision) Status
        +status(execution_id) Status
        +pilot_result(execution_id) PilotResult
        +resume(execution_id, approval) Status
        +cancel(execution_id) Status
        +result(execution_id) Result
    }

    class Revision {
        +String study_id
        +int revision
    }

    class Status {
        <<state-refined union>>
        +UUID execution_id
        +Revision revision
        +LifecycleState state
    }

    class PilotOutcome {
        <<outcome-refined union>>
        +Outcome outcome
        +CandidateId candidate_id
        +int plan_count_per_side
        +int attacks_per_plan
    }

    class Selection {
        +CandidateId candidate_id
        +int plan_count_per_side
        +int attacks_per_plan
    }

    class PilotResult {
        +precision_pilot_v1 method
        +lowest_predicted_runtime selection_rule
    }

    class PilotCandidate {
        +CandidateId id
        +int plan_count_per_side
        +int attacks_per_plan
        +number predicted_runtime_ms
    }

    class PilotAssessment {
        +float guarded_half_width
        +bool informative
        +bool passes
    }

    class ComparisonIdentity {
        +Tier tier
        +int budget
        +Strategy alternative
        +Strategy reference
        +String outcome
    }

    class Result {
        +UUID execution_id
        +Revision revision
    }

    class ResultFamily {
        +String id
        +holm method
        +float alpha
    }

    class ResultComparison {
        +typed statistics
        +Holm adjustment
    }

    class ResultTiming {
        +tier-keyed timings
    }

    class TierTiming {
        +five measured replicas
    }

    class ReplicaTiming {
        +int plan_selection_us
        +int simulation_us
        +int total_us
    }

    class Tier {
        <<enum>>
        small
        medium
        large
    }

    class StudyError {
        +ErrorCategory category
    }

    class ErrorIssue {
        +String code
        +Path path
        +String message
        +Map details
    }

    StudyFacade ..> Revision : creates
    StudyFacade ..> Status : returns
    StudyFacade ..> PilotResult : returns
    StudyFacade ..> Result : returns
    StudyFacade ..> StudyError : returns on failure

    Status "1" *-- "1" Revision
    Status "1" o-- "0..1" PilotOutcome
    Status "1" o-- "0..1" Selection
    Status "1" o-- "0..1" StudyError

    PilotResult "1" *-- "1" PilotOutcome
    PilotResult "1" *-- "1..*" PilotCandidate
    PilotCandidate "1" *-- "1..*" PilotAssessment
    PilotAssessment "0..*" --> "1" ComparisonIdentity

    Result "1" *-- "1" Revision
    Result "1" *-- "1" PilotOutcome
    Result "1" *-- "1" Selection
    Result "1" *-- "1" ResultFamily
    Result "1" *-- "1" ResultTiming

    ResultFamily "1" *-- "1..*" ResultComparison
    ResultComparison "0..*" --> "1" ComparisonIdentity
    ComparisonIdentity "0..*" --> "1" Tier

    ResultTiming "1" *-- "3" TierTiming
    TierTiming "1" *-- "5" ReplicaTiming

    StudyError "1" *-- "1..*" ErrorIssue
```

Public structure rules:

- `NetworkDefense.Evaluation2.Study` is the only supported facade.
- Public views are transient. They do not add persistence records.
- `Status` and `PilotOutcome` use discriminated unions.
- Pilot and Final results share `Study.Comparison` identities.
- Public statistics are typed values. Python maps stay at the transport boundary.

### Internal persistence and execution ownership

```mermaid
classDiagram
    direction LR

    class StudyRevision {
        +UUID id
        +String study_id
        +int revision
        +Definition definition
    }

    class StudyExecution {
        +UUID id
        +UUID study_revision_id
        +LifecycleState state
        +PilotOutcome pilot_outcome
        +Selection selection
        +StudyError error
    }

    class StudyPhase {
        +UUID id
        +UUID study_execution_id
        +PhaseKind phase
    }

    class StudyPhaseRun {
        +UUID id
        +UUID study_phase_id
        +RunKey key
        +GustRunId gust_run_id
    }

    class CollectionPlan {
        +UUID id
        +UUID study_phase_run_id
        +WorkItem items
    }

    class WorkItem {
        +int comparison_position
        +Side side
        +GraphRevision graph_revision
        +Strategy strategy
        +Seed selection_seed
        +Seed evaluation_root
        +int attack_count
    }

    class CollectionItem {
        +UUID id
        +UUID study_phase_run_id
        +ReplicaPosition replica_position
        +int item_position
        +UUID optimization_run_id
        +UUID experiment_id
    }

    class EvidenceSnapshot {
        +UUID id
        +UUID study_phase_id
        +Evidence evidence
    }

    class Evidence {
        +ordered comparison observations
    }

    class StudyResult {
        +UUID id
        +UUID study_execution_id
        +CorrectedFamily family
        +Timing timing
    }

    class GustRun {
        <<external>>
    }

    class OptimizationRun {
        <<external>>
    }

    class SimulationExperiment {
        <<external>>
    }

    StudyRevision "1" *-- "0..*" StudyExecution : executions
    StudyExecution "1" *-- "0..4" StudyPhase : phase groups
    StudyExecution "1" *-- "0..1" StudyResult : successful Final output

    StudyPhase "1" *-- "1..*" StudyPhaseRun : run links
    StudyPhase "1" *-- "0..1" EvidenceSnapshot : collection evidence

    StudyPhaseRun "1" --> "1" GustRun : identifies
    StudyPhaseRun "1" *-- "0..1" CollectionPlan : collection runs only
    StudyPhaseRun "1" *-- "0..*" CollectionItem : replica effects

    CollectionPlan "1" *-- "1..*" WorkItem : resolved requests
    CollectionItem ..> CollectionPlan : selects by item_position
    CollectionItem "0..*" --> "0..1" OptimizationRun : reserves and reuses
    CollectionItem "0..*" --> "0..1" SimulationExperiment : reserves and reuses

    EvidenceSnapshot "1" *-- "1" Evidence : contains
```

Internal structure rules:

- The internal UUID of `StudyRevision` stays private. Public code uses `{study_id, revision}`.
- Every Gust run has one `StudyPhaseRun`; `StudyPhase` stores no run or output cache.
- Collection phases own snapshots. Collection phase runs own plans and items.
- One immutable `CollectionPlan` stores resolved Evaluation2 `WorkItem` requests.
- `CollectionItem` stores positions and retry-safe effect links, not work copies.
- Gust owns detailed run and task status. Evaluation2 owns study lifecycle state.
