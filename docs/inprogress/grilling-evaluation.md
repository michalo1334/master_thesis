# Evaluation simplification

Status: staged implementation is authorized. The lead owns design and acceptance; interactive Sol agents implement the stages. See the rebuild plan and stage handoffs for runtime status. Earlier sections record the design discussion, including superseded proposals.

This record separates observed code behavior, proposed changes, and user decisions. A recommendation is not an accepted decision.

## User intent

The user wants a declarative way to specify evaluation and study behavior. The design must support experimentation as that behavior changes.

A person or AI agent must be able to understand the steps and their relationships quickly. Changes must not require edits across large amounts of procedural code. New libraries and useful abstractions are acceptable, even when a smaller fixed workflow would not need them.

The user explicitly requested a diagram of the relationships and pipeline before further design decisions. Schema validation is one supporting concern, not the full target.

The user then added durable execution as a requirement. The DAG is part of a larger workflow. Paid Oban Pro is out of scope. The user asked to step back from Runic and the Python sweep question to explore [Gust](https://github.com/marciok/gust), including its source code.

This is a prototype, not a production-hardening exercise. Full recovery across incompatible deployments is deferred. A Gust fork for versioning is a possible later path, not an instruction to fork it now.

## Decision tree

```text
Evaluation simplification
├─ Goals
│  ├─ Design target: declarative evaluation and study [Q1]
│  ├─ Success measure: clear steps and low-cost changes [Q1]
│  └─ Acceptance example: pending
├─ Contracts
│  ├─ Current consumers: Elixir, CLI, HTTP, dashboard [F1]
│  ├─ Interchange: typed JSON snapshots in DB [Q11]
│  ├─ Archive compatibility: not retained [Q11]
│  ├─ Specification shape: composed small structs [Q13]
│  ├─ Config references: nested typed structs [Q13]
│  ├─ Analysis settings: evaluation-owned [Q13]
│  ├─ Other compatibility limits: pending
│  ├─ Schema authority: pending
│  ├─ Contract libraries: Ecto + Pydantic [Q14]
│  ├─ Coercion policy: pending
│  └─ Other legacy support: pending
├─ Structure
│  ├─ Mixed responsibilities: confirmed [F2]
│  ├─ Current pipeline: mapped [M1]
│  ├─ Workflow freedom: executable DAG [Q2]
│  ├─ Runtime boundary: Gust schedules Python stages [Q6]
│  ├─ Data bindings: comments and ordinary task code [Q9]
│  ├─ Python server: compute-only HTTP responses [Q10]
│  ├─ Integration blueprint: proposed [M2]
│  ├─ DAG grouping: one shared study DAG [Q12]
│  ├─ Implementation: interactive Sol stages [Q15]
│  ├─ Obsolete code/tests: delete [Q15]
│  ├─ Validation boundary: pending
│  ├─ Result model: typed JSON; fields pending [Q11]
│  └─ Pilot boundary: pending
├─ Declarative models
│  ├─ Existing declarations: study data, fields, dataclasses [F3]
│  ├─ Orchestration direction: Gust with Python stage server [Q6]
│  ├─ Sweep declarations: deferred [Q4]
│  ├─ Output declarations: pending
│  └─ Dependency budget: libraries and abstractions allowed [Q1]
├─ Durability
│  ├─ Required execution: durable subworkflow [D1]
│  ├─ Paid dependencies: Oban Pro excluded [D1]
│  ├─ Recovery boundary: restart interrupted stage [Q7]
│  ├─ Parent authority: unspecified
│  ├─ Definition model: pending [Q5]
│  └─ Definition versions: deferred for prototype [Q8]
└─ Verification
   ├─ Statistical invariants: identified [F4]
   ├─ Safety invariants: identified [F5]
   ├─ Regression evidence: pending
   └─ Migration sequence: pending
```

The question and fact IDs refer to the sections below. Branches will change as the interview resolves dependencies.

## Review findings

These findings concern the Python analysis package and its Elixir consumers. The review does not establish that the whole Elixir evaluation engine needs a rewrite.

| Priority | Finding | Evidence | Proposed change |
| --- | --- | --- | --- |
| 1 | Shape checks, scalar conversion, and relational rules share validation code. | `evaluation/analysis/src/network_defense_analysis/contracts.py:88-477`; `evaluation/analysis/src/network_defense_analysis/study.py:366-731` | Use typed boundary schemas for structure. Keep cross-record rules as explicit domain checks. |
| 2 | Study transport, policy, final analysis, pilot selection, and packaging share one module. | `evaluation/analysis/src/network_defense_analysis/study.py:172-329`, `:738-1175` | Separate these responsibilities by the reason each changes. Do not split files without reducing coupling. |
| 3 | One analysis function loads data, computes statistics, builds result rows, and writes artifacts. | `evaluation/analysis/src/network_defense_analysis/report.py:276-505` | Separate computation from result construction and file writing. Pass typed intermediate results. |
| 4 | Python and Elixir repeat study-shape and coercion rules. | `evaluation/analysis/src/network_defense_analysis/study.py`; `src/lib/network_defense/evaluation/contracts/study_specification.ex:1-27`, `:200-280`, `:350-470` | Decide who owns the external contract before choosing a schema library. |
| 5 | Output field lists are declared, but result assembly and writing remain repetitive. | `evaluation/analysis/src/network_defense_analysis/report.py:15-88`, `:470-502`; `evaluation/analysis/src/network_defense_analysis/study.py:44-56` | Consider a small output registry or derive fields from row models. Preserve explicit ordering. |
| 6 | CLI and HTTP repeat parts of the archive lifecycle. | `evaluation/analysis/src/network_defense_analysis/cli.py:18-104`; `evaluation/analysis/src/network_defense_analysis/service.py:54-190` | Share application operations. Keep CLI behavior and HTTP policy in their adapters. |

The main opportunity is to remove repeated knowledge, not only shorten files. Moving the same branches into more modules is not enough.

## Direction after clarification

First identify the current workflow, its data artifacts, and the policies that connect its stages. Separate automatic execution from manual decisions. Then decide which relationships the future declarations must express.

The target can include reusable steps, declared dependencies, interchangeable analysis methods, and explicit output definitions. These are candidates, not accepted design details.

Do not limit the discussion to shape validation or a fixed pipeline. Equally, do not choose a workflow engine before identifying the behavior it must express.

### Schema candidates only

The following candidates address boundary schemas, not workflow composition. The Python package currently declares no schema library. It targets Python 3.12. See `evaluation/analysis/pyproject.toml`.

| Candidate | Useful when | Limits or decisions |
| --- | --- | --- |
| Pydantic | Python owns typed validation models and needs structured validation errors. | Configure coercion explicitly. Keep archive I/O and relational rules outside the models. |
| msgspec | Typed JSON decoding and compact boundary declarations are the main needs. | Check compatibility with existing numeric strings and custom error requirements. |
| JSON Schema with language-specific validators | Python and Elixir need a portable JSON contract. | It does not cover CSV relationships, filesystem safety, or statistical rules. Check validator and dialect support on both sides. |
| Existing dataclasses | Internal computed results need clear types without a new dependency. | Dataclasses alone do not remove the current input-validation boilerplate. |

Choose schema and workflow tools after their responsibilities are clear. Different layers can use different libraries when this reduces custom code and keeps the execution path visible.

## Goals

### Q1 — Refactor scope

**Question:** Should this refactor cover only Python analysis, or also the Elixir code that repeats its contracts?

**Recommendation:** Cover Python analysis and the directly related Elixir contract boundary. Keep the evaluation engine and dashboard redesign outside the initial scope.

**Reason:** A Python-only change can simplify the analysis pipeline, but it leaves the duplicated cross-language contract unresolved. A whole-system rewrite adds unrelated risk.

**Options:**

1. Python plus contract boundary — include the directly related Elixir schemas and consumers when needed.
2. Python only — simplify `evaluation/analysis/`; leave Elixir contracts unchanged.
3. Whole evaluation system — also review and refactor Elixir execution, tasks, and dashboard integration.

**User answer, summarized:** Focus the interview on declarative specification of evaluation and study behavior. The behavior can change. A person or AI agent must understand the steps quickly and make experimental changes without editing thousands of lines of procedural code. Libraries and additional abstractions are acceptable.

**Further user request:** Identify the relationships and pipeline. Show them in a diagram.

**Effect on the recommendation:** The original focus on Python cleanup and boundary validation was too narrow. Map the whole evaluation/study workflow before fixing implementation scope or choosing libraries.

**Rejected direction:** Treating shorter validation code as the complete solution.

### Success measure

Accepted direction: understandable steps and relationships, with low-cost experimental changes. Additional abstractions are allowed when they support this direction.

Pending: select a concrete example change that will test the design. A lower line count alone does not prove that experimentation became easier.

## Contracts

### F1 — Current consumers

Observed: the archive and result formats cross several boundaries.

- Elixir writes evaluation archives: `src/lib/network_defense/evaluation/output_contract.ex`.
- Python validates them: `evaluation/analysis/src/network_defense_analysis/contracts.py`.
- CLI and HTTP expose analysis operations: `cli.py` and `service.py` in the Python package.
- Elixir reads analysis results: `src/lib/network_defense/evaluation/analysis/analysis_result.ex`.
- The dashboard displays derived results: `src/assets/svelte/dashboard/analysis-report/`.
- Semantic comparison excludes run identity and runtime fields: `evaluation/analysis/src/network_defense_analysis/compare.py`.

Pending decisions: contract authority, allowed breaking changes, error compatibility, coercion, JSON/CSV ownership, schema versions, and legacy archive support.

Current code accepts selected numeric strings. Do not let a library's default coercion silently define new behavior.

The Elixir result reader supports legacy `analysis.json` plus `metadata.json` archives. That support is a migration decision, not automatic dead code.

## Structure

### M1 — Current pipeline

The [pipeline and relationship diagrams](evaluation-pipeline.md) map collection, study preparation, Pilot and Final analysis, result verification, and manual handoffs.

The map distinguishes data dependencies, scientific policies, and human decisions. The current study specification selects and validates existing evidence; it does not launch collection. Pilot does not automatically produce or analyze Final evidence.

### Q2 — Workflow freedom

**Question:** Should study declarations define the executable DAG of steps and dependencies, or configure a fixed collection, Pilot, and Final lifecycle?

**Recommendation:** Declare an executable DAG of named steps with typed inputs and outputs. Keep numerical and simulation algorithms in implementation functions. Represent manual handoffs explicitly. Validate required evidence rules separately from graph structure.

**Reason:** This makes the steps visible and supports changes to the procedure, not only changes to its parameters. It does not, by itself, require a distributed scheduler or a new configuration language.

**Options:**

1. Executable DAG — declarations can add, replace, and connect steps as well as choose methods and policies.
2. Fixed phases, flexible methods — keep collection, Pilot, and Final fixed; allow replaceable analysis and selection methods within them.
3. Fixed workflow, policy values — keep the stage graph and methods fixed; declare comparison sets, sample sizes, and other values.

**Session note:** The previous question was interrupted by a session restart. No option was selected. The user requested the question again.

**User follow-up:** A DAG library may be a natural fit because steps have dependencies rather than one linear order. The user suggested [Runic](https://github.com/zblanco/runic) as an example. Its fit is under review; no library is selected.

**User answer:** Executable DAG.

**Accepted direction:** Declarations define named executable steps and their dependencies. The DAG is not only a diagram of a hardcoded procedure.

**Rejected alternatives:** A fixed lifecycle or parameter-only configuration as the main design.

### Q3 — Runtime boundary

**Question:** How should the executable DAG cover Python analysis as well as Elixir collection?

**Recommendation:** Use native DAGs in each runtime, with explicit subgraph boundaries and a composed view. Keep numerical data and algorithms in Python. Let the Elixir graph invoke analysis operations without turning every statistical function into a remote endpoint.

**Reason:** Runic can expose the Elixir workflow, but it cannot discover or execute a Python subgraph automatically. A coarse Python call alone would leave much of the original analysis workflow hidden.

**Options:**

1. DAG per runtime — each runtime owns its steps. A composed view shows the Python subgraph behind the Elixir analysis step.
2. Elixir DAG calls Python stages — one central Elixir graph dispatches individual analysis stages to Python.
3. Elixir DAG; Python opaque — use a DAG for outer orchestration only. Keep Python analysis behind Pilot and Final calls.

**User answer:** DAG per runtime. The user then asked whether Python would use a sub-DAG library.

**Initial accepted direction:** Elixir and Python each own their internal DAG. The Python graph sits behind an Elixir analysis-operation node. It is not a Runic-native nested component or a shared cross-language executor. The user later reopened this boundary by proposing a Python stage-execution server; see Q6.

**Follow-up:** Evaluate Python DAG libraries for the existing analysis process. Another service or distributed scheduler is not required by this decision alone. The later durability requirement needs a separate decision about persisted progress and recovery across both runtimes.

**Superseded by Q6:** The user later selected Gust scheduling individual stages on a persistent Python server. Separate Python DAG scheduling is no longer the selected direction.

### Q6 — Python stage server

**User proposal:** Instead of treating the analysis service as one opaque operation, make it a server whose analysis stages participate in the DAG.

**Question:** Should Gust dispatch individual Python stages when dependencies are ready, or submit a complete Python sub-DAG for the server to schedule?

**Recommendation:** If the goal is one durable graph with visible Python-stage progress, let Gust schedule registered Python stages. Python executes stage implementations and returns results; it does not need another dependency scheduler. This is a proposed integration, not a built-in Gust remote-stage guarantee.

**Boundary, refined by Q10:** Send a registered stage identifier and complete inputs, parameters, and seed policy. Return the completed result in the HTTP response. Do not require arbitrary Python source, a durable Python operation identity, or state left by earlier requests. Choose payload shapes and stage granularity from representative data sizes.

**Durability, refined by Q10:** A successful Gust task returns the decoded response map with result storage enabled. Gust persists that completed task result. An interrupted or ambiguous HTTP request may be recomputed with the same inputs and seed policy; Python does not expose operation lookup or background job status. This is semantic idempotence, not execution deduplication.

**Options:**

1. Gust schedules every stage — one durable dependency graph; Python is a remote stage executor.
2. Python schedules its sub-DAG — Gust submits a graph definition or named subgraph operation; Python owns internal readiness, retries, and checkpoints.

**User answer:** Gust schedules stages.

**Accepted direction, refined by Q10:** One durable dependency scheduler in Gust. The persistent Python service executes registered stages through stateless compute-only HTTP requests and returns their results. Gust owns progress and saved task results. Python has no operation/job registry. This does not require GustPy or a separate Python DAG scheduler.

**Effect on Q3:** Supersedes the earlier DAG-per-runtime scheduling decision. Numerical implementations remain in Python.

**Still open:** Exact stage granularity, typed JSON schemas, snapshot source mapping, payload size limits, and HTTP timeout/cancellation behavior. Q11 removes binary archive/report handling from the target. Internal checkpoints and deployment-version hardening are deferred.

### Q9 — Data bindings

**Question:** Should the DAG declare which named stage outputs feed which stage inputs, or only declare execution order while stage code retrieves upstream results?

**Recommendation:** Declare input/output bindings. Derive ordinary data dependencies from those bindings and keep additional control dependencies explicit. Python stages receive resolved inputs rather than looking up unrelated task names themselves.

**Reason:** An ordering edge alone does not specify which artifact or result field becomes a Python parameter. Leaving these lookups inside every stage preserves hidden coupling and repeated transport code.

**Options:**

1. Dependencies and data bindings — the declaration connects named outputs to inputs. A shared integration layer resolves references and prepares stage requests.
2. Execution order only — Gust orders tasks; individual task implementations find and interpret upstream outputs.

**Scope:** This chooses binding semantics, not a configuration syntax or a custom graph language. The binding layer is proposed application integration, not a claimed built-in Gust feature.

**Earlier user request:** Show how both choices would look in Elixir before selecting an option. The later choice appears below.

**Illustrative examples:** `RemotePython.run!` is a proposed client helper, not an existing module. It represents a stage call returning a map of named output references. Operation identity, waiting, and error handling are omitted here. The single-result lookup assumes an unmapped upstream task.

Execution ordering with native Gust task structure:

```elixir
defmodule Example.OrderOnly do
  use Gust.DSL
  alias Gust.Flows

  task :comparisons,
    downstream: [:estimate],
    ctx: %{params: params},
    save: true do
    RemotePython.run!(:build_comparisons, %{
      "evidence" => params["evidence"]
    })
  end

  task :estimate, ctx: %{run_id: run_id}, save: true do
    [comparisons] = Flows.get_tasks_by_name("comparisons", run_id)

    RemotePython.run!(:estimate_effects, %{
      "matrix" => comparisons.result["matrix"]
    })
  end
end
```

Named bindings as plain Elixir data, consumed by a proposed shared Gust integration:

```elixir
defmodule Example.WithBindings do
  def stages do
    [
      comparisons: [
        python: :build_comparisons,
        inputs: %{evidence: {:input, :evidence}}
      ],
      estimate: [
        python: :estimate_effects,
        inputs: %{matrix: {:output, :comparisons, :matrix}}
      ]
    ]
  end
end
```

The second form is not native Gust syntax. The integration resolves run inputs and upstream output references, derives the data-dependency edge, and prepares stage requests. Extra control dependencies remain separate. The lookup still happens at runtime, but one shared resolver owns it rather than every task body. The numerical Python functions need not change between the two options.

**User answer:** Do not add a data-binding declaration. Describe the data flow in comments instead.

**Decision:** Use ordinary Gust dependency declarations and task code. Comments explain named inputs, upstream sources, outputs, and consumers. No binding compiler, custom binding DSL, or generated dataflow layer is required for the prototype.

**Contract checks:** Typed stage request/response validation can remain; it is separate from an executable binding declaration. Comments document relationships but do not enforce them.

**Rejected direction:** The proposed executable input/output binding layer for now.

### M2 — Integration blueprint

**User questions:** How should the shared layer be built? How difficult and verbose is it? What are all the currently planned study/specification stages? What could the Python REST interface look like?

**Detailed answer:** [Prototype integration design, full stage catalog, API examples, and estimates](evaluation-stage-integration.md).

**Status after user feedback:** The data-binding compiler is rejected for now. The Python server must be idempotent and stateless. The following records the earlier, heavier proposal; its operation-server design and size estimates are not the current agreed design.

**Earlier proposed approach:** A small binding compiler emits normal Gust task declarations using the existing reusable `task_action` / `Gust.Action.execute/2` hook. One remote-stage action owns input resolution, stable operation identity, submission, and status polling. Python owns registered implementations, operation execution records, and stored outputs, not DAG scheduling.

**Complexity assessment:** Binding notation is small. Mapped references and durable remote operation/output handling are medium-complexity integration work. The unimplemented estimate is roughly 800–1,450 lines of support code before tests and domain refactoring. This is not a measured size or delivery promise. Workflow definitions should remain tens of lines, but total code likely grows initially.

**Stage scope:** Common specification/evidence preparation; Pilot grid/evaluation/selection/report; Final estimation/family correction/report; shared verification/publication. Existing detailed-report families and collection operations are inventoried separately, not silently added to the first slice or to the Final study ZIP.

**API proposal:** Stage catalog, artifact upload/download, idempotent operation creation/lookup, status, and cancellation. Requests contain registered stage names and artifact references, not arbitrary Python source or a second executable DAG.

**Prototype default under discussion:** Service-owned operation/artifact tables in the existing PostgreSQL instance for modest artifacts. No storage backend is approved yet. No object store, fork, deployment-version fleet, or implementation is authorized by this design answer.

**Review evidence:** The action hook and literal Gust DSL loading were inspected in the cloned source. Independent design review prompted explicit operation states, atomic attempt claims, mapped-result key validation, and archive-compatibility checks. No runtime probe or tests ran.

### Q10 — Stateless Python server

**User requirement:** The HTTP server must be idempotent and stateless.

**Clarification needed:** Does this mean synchronous compute-only stage requests, with Gust/application storage owning execution state and saved results, or stateless HTTP instances backed by a durable asynchronous operation store?

**Recommendation:** For the simpler prototype, use a compute-only stage API and let Gust own stage progress and retries. Each request supplies its complete typed JSON input. Idempotence means repeated effective inputs and seeds produce the same scientific result; it does not promise that computation happens only once.

**Persistence boundary, refined by Q11:** Save typed input snapshots and results as database JSON. Gust saved task results provide persistence for intermediate maps. Check larger payload sizes and stage granularity; do not introduce an archive or artifact service by default. A stateless Python process alone does not provide completed-output reuse.

**Options:**

1. Compute-only stage server — requests return completed results; no Python job/operation registry. Gust owns retry/progress state and persists the outputs.
2. Stateless API with durable jobs — HTTP instances have no local session state, but an external operation store and executor still provide submit/status/result behavior.

**User answer:** Compute-only server. The user suggested returning results directly in the HTTP response.

**Decision:** Use synchronous stage requests and return completed results in the response body. No Python operation table, background job registry, submit/status API, polling, callbacks, or server-side result lookup is required for this design.

**Completed-output persistence:** For JSON-sized intermediate results, the Gust task returns the decoded response map with `store_result: true`. Gust persists it for downstream tasks and recovery. No dedicated artifact store is needed merely for these values.

**Request contract:** Supply all required inputs and explicit seeds. Do not depend on earlier Python requests, process-local caches, or temporary paths. Repeated effective inputs produce the same scientific result; a lost response may cause duplicate computation.

**Format decision, refined by Q11:** No ZIP or binary report contract is needed. Input snapshots and result data use typed JSON, saved in the database and displayed in the existing dashboard.

### Q11 — Typed JSON instead of archives

**User feedback:** Why retain a deterministic archive bundle and `study.load_evidence` instead of typed contracts? Remove the ZIP bundle and everything related to it. Use the existing dashboard to display data. Replace ZIP loading with saving/loading JSON in the database.

**Decision:** Use typed JSON contracts for evidence, stage inputs, intermediate values, and final results. Elixir prepares a snapshot from selected persisted evaluations and saves the full required input as database JSON. It loads that JSON into HTTP requests. Python validates the request, computes the stage, and returns typed JSON. Elixir/Gust saves the response; the existing dashboard displays the data.

**Removed from the target:** Archive bundle creation, `study.load_evidence` as a ZIP-loading task, archive extraction, file-member manifests, checksums, archive-related CSV/string conversion, file-result adapters, report packaging, and ZIP download paths. Do not replace ZIP with base64 ZIP or a different archive. Do not retain ZIP compatibility as a requirement.

**Retained:** Typed-model validation and scientific checks for compatible evidence, seeds, shared attacks, crossed samples, family completeness, and correction scope. Evaluation configuration and scientific metadata remain domain data; they are not archive manifests.

**Stage changes:** S3 becomes preparation/persistence of a typed input snapshot. Former S4 is removed; boundary validation is ordinary model/helper logic. Pilot/Final result assembly produces JSON. Existing dashboard presentation replaces file-oriented reporting; no additional display system is required.

**Snapshot semantics:** Save the actual observations/configuration needed by later stages, not only IDs that cause retries to reread potentially changed source data. Gust's saved task result can hold an initial snapshot; choose a separate application row only if domain/query needs warrant it. Python needs no database client for this boundary.

**Library status, refined by Q14:** Typed contracts and Ecto plus Pydantic are selected. Exact model fields and dependency versions remain implementation work.

**Implementation status:** This updates the design, not runtime code. Current ZIP paths remain until implementation is requested. Preserve numerical results and dashboard data meaning, not legacy file layouts.

### Q12 — DAG grouping

**User question:** Are Specification, Pilot, and the other sections separate DAGs?

**Clarification:** Specification is input data, not a DAG. The stage catalog groups tasks by responsibility; a heading does not establish a separate Gust definition or run. One scheduler can run either one study DAG or several phase DAGs.

**Recommendation:** Start with one shared study DAG definition. Each study execution creates its own run. Preparation, Pilot, the manual Final-input gate, Final, and result persistence are sections of that DAG, not opaque Python calls. Prepare a separate Final JSON snapshot after the gate; Pilot candidate results are not Final observations.

**Options:**

1. One study DAG — phases share a run; the workflow waits for the manual handoff and new Final evidence.
2. Separate phase DAGs — Pilot and Final have separate definitions/runs; the application or an outer workflow links them and owns the handoff.

**User answer:** One study DAG.

**Decision:** Use one shared Gust DAG definition and a new run for each study execution. Pilot and Final are task sections in the same run. Save the Pilot result before waiting for manually supplied Final inputs. Continue with a separate Final evidence snapshot, then save the Final result.

**Task identity:** Reused implementations have distinct phase-specific task instances, such as preparing Pilot input and preparing Final input. Do not create a cycle by returning to the same preparation node.

**Scope:** No phase-DAG launcher, parent/child DAG coordination, data-binding DSL, Python scheduler, or native nested-DAG feature is required. Final collection remains manual unless separately approved. This grouping decision does not require arbitrary runtime graph construction or production version management.

### Q13 — Specification composition

**User proposal:** Replace the giant specification struct with smaller structures. The top-level Specification contains fields that point to stage-related data instead of all individual settings.

**Accepted direction:** Compose smaller typed specification/configuration contracts. This is data modeling, not an executable data-binding declaration or another DAG.

**Recommendation:** Each stage receives only the configuration it needs. Shared scientific rules have one owner and are reused by Pilot/Final rather than independently copied. Keep configuration separate from mutable execution state and computed results. Prefer nested typed structures in one saved JSON specification for the prototype unless independent configuration reuse requires separate records.

**Clarification question:** Should these fields embed typed configuration structures, or reference separately stored configuration records by ID?

**Options:**

1. Nested typed structures — small models compose the specification and serialize into one JSON document. No extra tables or reference-resolution layer.
2. Separate configuration records — the specification stores IDs. Records can be shared independently; an execution must resolve and snapshot them before running.

**Research findings:** The persisted row in `src/lib/network_defense/evaluation/study_specification.ex` is already small: identity/version/title plus one `content` map. `study_specifications.ex` treats saved versions as immutable. The large scientific contract/validation lives in `src/lib/network_defense/evaluation/contracts/study_specification.ex`. Its current groups cover tiers, shared comparison family, Pilot settings, correction, and two phase seed schedules. Python already has a smaller `PilotConfiguration` type in `study.py`.

**Proposed initial groups:**

| Type | Responsibility |
| --- | --- |
| PreparationSpec | Tier declarations and one schedule object per phase, with disjointness checked across phases |
| ComparisonSpec | Shared alternatives, reference, budgets, and outcome/family definition |
| PilotSpec | Candidate grid, precision target, guard/subsamples, and selection policy |
| CorrectionSpec | Correction method and complete-family invariant |

These are proposed type names and boundaries, not implemented structs. Root fields compose the small contracts. Existing row identity/title/version stay persistence metadata. No empty FinalSpec or result/report configuration type is needed just to mirror every DAG task.

**Ownership decision:** The user accepted preserving the existing ownership. Common confidence/bootstrap/permutation/analysis-seed settings remain with the selected evaluation inputs and are checked by `study_input_compatibility.ex`. The specification cleanup does not move them into a study-owned AnalysisSpec. Carry the validated settings in the typed execution input when a stage needs them. Selected evaluation run IDs and computed results remain execution/input data, not scientific configuration.

**Shared-rule caution:** Reuse one comparison policy across Pilot/Final. A schedule type may have distinct Pilot and Final instances; do not copy both schedules or the whole family into independently editable phase configurations.

**User answer:** Nested typed structs.

**Decision:** The root composes smaller typed configuration structures. Serialize the composition as one JSON document; do not add separate configuration IDs/tables or a reference-resolution layer. The existing persisted identity/title/version wrapper can remain separate from the typed configuration content. Exact type boundaries above remain a proposal. Q14 subsequently selects Ecto plus Pydantic.

**Stage usage:** Pass each stage only the small configuration objects it needs, alongside its typed input data. Do not pass the entire Specification to every helper. One configuration type can serve multiple tasks; no one-to-one type/task rule is required.

### Q14 — Contract implementation

**User request:** Next steps after accepting the specification composition and preserved analysis-setting ownership.

**Recommended sequence:** Define concrete configuration/input/result contracts; implement database JSON snapshots; expose stateless JSON stage calls; wire one Gust study DAG through Pilot, the manual gate, and Final; verify numerical/dashboard behavior and remove archive-only paths. This is a proposed work sequence, not implementation authorization.

**Next question:** Use Ecto embedded schemas for Elixir configuration and Pydantic for Python stage inputs/results, or retain Python dataclasses and explicit validation?

**Recommendation:** Reuse existing Ecto facilities for the nested Elixir-owned specification. Use Pydantic for the Python stage API contracts to avoid replacing one large manual validator with another. Python needs stage-specific request/result models, not a duplicate of the complete persisted study specification. No schema generator or new binding DSL is required.

**Options:**

1. Ecto plus Pydantic — native nested models and model validation; adds a Python dependency.
2. Ecto plus Python dataclasses — avoids that dependency; request parsing and validation remain more explicit.

**User answer:** Ecto plus Pydantic. First remove the legacy analysis setup so it does not confuse the implementor on a new worktree.

**Decision:** The contract stack is selected. The user then requested staged implementation by interactive Sol subagents, with lead-owned plan/design and direct user guidance. Cleanup precedes the new contracts. Dependency versions and exact fields remain stage work; no package installation occurred in the design discussion.

### Q15 — Staged implementation and pristine code

**User direction:** Split implementation into major stages. Launch an `openai/gpt-5.6-sol` subagent for each stage. The user will direct the agent to catch mistakes. The lead owns the plan, design, and high-level intent.

**Standing boundary:** Always purge obsolete behavior and its tests. The current tree contains only relevant code. Recover old implementations from Git history, not compatibility branches, disabled tests, legacy directories, backup copies, or commented-out code.

**Execution agreement:** Use interactive stage agents in dependency order. Each agent owns implementation/testing of its current stage, not the next stage. The lead reviews stage acceptance and coordinates handoffs. Clarify ambiguous shared-code boundaries before removal; preserve unrelated working changes and stored evaluation data.

**Workspace decision:** The user selected one worktree common to all stages. Use `/home/michalo/master_thesis-evaluation-rebuild` on branch `evaluation/rebuild`, created from `d94ba40352e469dc1c2da403ad3fa28397e5e350`. Keep the original source worktree's unrelated changes untouched. Future stage agents use this same directory, not separate stage worktrees.

**Stage 1 scope correction:** Remove the completed-evaluation ZIP export/download route too; no independent ZIP exception was approved. Retain the old specification validator only while the editor/save/preview still uses it. Delete StudyInputCompatibility and its tests if no retained callers remain. Scientific requirements remain in the design, not unused legacy code.

**Migration policy:** Migrations can be destructive. The user explicitly requires no preservation: obsolete schema, migration history, and existing database records need not survive. Stage 1 can rewrite the current schema and recreate project databases. Do not retain compatibility layers or legacy migration chains solely to preserve old data. Verify the database target before destructive commands; unrelated databases/infrastructure remain outside scope. Current retained functionality still needs a correct fresh schema. This supersedes earlier data/schema-preservation constraints.

**Latest Stage 1 boundary:** The user removed the evaluation directory and requested a clean slate for the entire evaluation directory/code, not only Python analysis. Remove all remaining evaluation-owned callers, study/specification/report UI, contracts, tests, configuration, scripts/infra, and schema. Do not restore the deleted directory or recreate missing evaluation modules to make old tests compile. Earlier instructions to retain evaluation collection/reporting/specification behavior are superseded. Keep only genuinely independent current graph/simulation/optimization/application behavior.

**Methodology requirement:** Preserve the scientific methodology in documentation so the evaluation code can be rewritten. Recover the method from Git baseline `d94ba40352e469dc1c2da403ad3fa28397e5e350`; do not preserve obsolete executable implementations, archive formats, or setup paths for this purpose. The lead owns `docs/concepts/evaluation-methodology.md`, while the interactive Sol agent continues the expanded cleanup. This is current-stage documentation, not an upfront implementation plan.

**Major stages:** Legacy reset; typed contracts/data; stateless Python computation; Gust study workflow; dashboard integration/verification. The detailed contracts and acceptance criteria are in [the rebuild plan](evaluation-rebuild-plan.md).

**Deletion scope:** Apply the pristine-code rule throughout each approved stage. Remove replaced adapters, old tests, routes, configuration, and active setup documentation. Do not retain obsolete pieces merely to keep legacy tests passing. Valid shared behavior and scientific regression requirements remain relevant; express new tests through the current contracts.

### F2 — Mixed responsibilities

Observed: `study.py` combines transport, schema validation, study policy, analysis, pilot decisions, and result packaging. `report.analyze()` combines computation and presentation.

The current `_PrimaryComparison` type provides a useful intermediate model. Build on existing separation where it fits.

Pending decisions: exact typed result fields, single-run versus study reuse, Pilot selection boundaries, and useful module/stage granularity. Q11 removes shared archive operations from the target.

## Declarative models

### F3 — Existing declarations

Observed: study families, budgets, pilot settings, and seed schedules already exist as study data. Required archive members and output fields already have centralized declarations. Several internal records already use dataclasses.

The target is to carry that explicit structure through parsing, validation, computation, and output. It is not to convert every function into configuration.

Pending decisions: primary schema approach, added dependencies, output declarations, and whether one model should define both JSON and CSV output.

### Q4 — Sweep declarations

**Question:** Should repeated analyses, such as the Pilot candidate grid, be declared as sweeps that the DAG library expands, or as explicitly named sub-DAG instances?

**Recommendation:** Declare sweeps and mapping rules. Keep valid combinations, evidence constraints, seed identity, and cost checks in explicit domain policy. The library handles mapping and result collection, not the meaning of an experiment.

**Reason:** The user wants experimental changes without repetitive orchestration. A declared parameter space makes repetition visible instead of hiding loops inside a large node.

**Options:**

1. Declared sweeps — declare the valid candidates and mapped analysis; the runtime expands work and collects results.
2. Explicit variants — declare each named sub-DAG instance separately, reusing step implementations but not automatic sweep expansion.

**User answer:** No selection. The user asked to step back and investigate Gust with durable execution as a requirement.

**Status:** Deferred. Resume only after the durability and orchestration boundaries are clear.

**Rejected alternatives:** None yet.

### Runic review

[Runic](https://github.com/zblanco/runic) is an Elixir dataflow-workflow library. The user suggested it as a DAG candidate. It is not selected.

Confirmed in the official documentation:

- Named steps, dependency connections, joins, conditional rules, and collection fan-out/fan-in.
- Graph introspection, including authored components and the compiled execution graph.
- Mermaid and Graphviz output.
- Scheduling policies, retries, timeouts, checkpoints, and Runner persistence options.

Important limits and adoption questions:

- Runic executes Elixir components. Python stages require an explicit integration boundary.
- The package identifies itself as alpha. Pin and test the chosen version before adoption.
- A checkpoint does not make an external request atomic. Recovered work can repeat external effects.
- The current application already persists resumable evaluation runs. Decide which layer owns execution state and recovery before adding Runner persistence.
- A first-class human approval node was not confirmed. Keep approval state and resume semantics explicit in the application unless a suitable library mechanism is demonstrated.
- A DAG must remain acyclic. Pilot collection and Final collection can be separate node instances of the same operation. Repeating a study creates another execution; it need not add a backward edge.

Sources: [README](https://github.com/zblanco/runic/blob/main/README.md), [API cheatsheet](https://github.com/zblanco/runic/blob/main/guides/cheatsheet.md), [durable execution](https://github.com/zblanco/runic/blob/main/guides/durable-execution.md), and [package metadata](https://github.com/zblanco/runic/blob/main/mix.exs). This was a documentation review, not an integration test.

### Python DAG review

The user asked about a Python library for the analysis subgraph. The library runs inside the existing analysis process; no new service or shared cross-language executor is required.

| Candidate | Main fit | Main concern to check |
| --- | --- | --- |
| [pipefunc](https://pipefunc.readthedocs.io/) | Scientific pipelines, named outputs, mapped work, and parameter sweeps. | Reusable subgraph replacement, error context, mapped result identity, and API stability. |
| [Apache Hamilton](https://hamilton.apache.org/) | Typed function-based dataflow, modular stages, and parameterized sub-DAGs. | Whether candidate mapping remains clear without adding unnecessary framework features. |
| [Dask delayed](https://docs.dask.org/en/stable/delayed.html) | Lazy task construction and parallel execution. | Lower-level task graphs provide less domain structure for study definitions. |

**Recommendation:** Evaluate pipefunc first if sweeps are central to authoring studies. Hamilton is a strong alternative for modular named stages. This is a candidate for a small comparison, not a decision to adopt either library or permission to implement it.

Both leading candidates infer dependencies from function arguments and named results. Functions remain independently testable. Check that the inferred edges remain easy to inspect and that graph construction fails clearly on missing or incompatible inputs.

Python 3.12 is supported by the reviewed package metadata. Complete dependency compatibility with the project's pinned numerical packages still needs a check. No package was installed or integration test run.

A Pilot candidate evaluation starts from its comparison evidence. Candidate results are aggregated for eligibility and ranking; they must not be confused with the input observations used to construct a crossed comparison matrix. Final correction waits for the complete declared family of estimates.

Scientific seeds must remain explicit inputs. Scheduler order, parallel completion order, and library task keys must not silently redefine them. Caching must account for input identity, methods, configuration, versions, and seeds. Side-effecting output writers need separate retry and caching rules.

Additional sources: [pipefunc repository](https://github.com/pipefunc/pipefunc), [Hamilton function modifiers](https://hamilton.apache.org/reference/decorators/), [Hamilton visualization](https://hamilton.apache.org/concepts/visualization/), and [Dask best practices](https://docs.dask.org/en/stable/delayed-best-practices.html).

## Durability

### D1 — Durable subworkflow

**User requirements:** Durable execution as part of a larger workflow. Paid Oban Pro is excluded. Explore Gust as an alternative to Runic. Source inspection and a temporary clone are permitted.

**Source review:** Complete. See [Gust assessment, evidence, and proposed handoff diagram](gust-evaluation-review.md). The review confirmed PostgreSQL state, run leases, saved task outputs, external waits, and the callback ordering described in the pasted conversation. It also found limits in retry recovery, task-effect fencing, and definition versioning.

**Pasted conversation:** Most central claims are source-supported, but they are not complete guarantees. The review did not run crash tests. GustPy adds a Python execution option that the excerpt did not assess fully.

**Project finding:** Evaluation state is persisted, but study attempts and analysis results are currently browser-owned and temporary. A durable study requires backend ownership and durable result references, not only a new scheduler.

**Pending decisions:** Recovery granularity, parent workflow ownership, durable result storage, duplicate-start prevention, completion reconciliation, and definition compatibility across deployments. The larger parent workflow has not yet been identified.

**Working architecture:** Q6 selects Gust scheduling stages on a persistent Python server. This supersedes Q3's separate-scheduler model. GustPy and Runic are not required for that direction. Integration, versioning, and runtime guarantees still need design and verification. No package was installed and no implementation changed.

### Q5 — Definition model

**Question:** Must a study create arbitrary DAG shapes from runtime data without deployment, or can its executable graph be declared in versioned code?

**Recommendation:** Start with versioned DAG code. A study can still declare a different graph, replace stages, and expand mapped work. This does not restore a fixed lifecycle. Preserve the intended version for active runs and use new versions for new runs.

**Reason:** The stated users are a developer and an AI agent, both able to edit code. A runtime graph editor or arbitrary graph-data language is not yet a requirement. Gust fits code-defined DAGs more directly; immutable execution versions still need an application policy.

**Options:**

1. Versioned DAG code — code declares nodes and edges; data supplies inputs and mapped task items. Graph changes are versioned code changes.
2. Runtime-built DAGs — study data can define arbitrary new nodes and edges without deployment. Executable graph instances need durable snapshots; the reviewed Gust source does not establish this model.

**User clarification:** Asked whether different study stages simply mean conditional execution.

**Clarified distinction:** Conditional execution selects among already declared paths. Mapping repeats a declared task over tiers or candidates. Graph composition adds task types or dependency relationships that are not already present in the definition. These are separate capabilities.

**Revised starting recommendation:** One shared, versioned DAG with explicit conditions and mapped task expansion may be sufficient. Different graph definitions per study were a possible extension, not an established requirement. The executable-DAG decision does not imply arbitrary runtime graph construction.

**Gust caveat:** In the reviewed readiness logic, any skipped upstream task causes the dependent task to skip. That can propagate through descendants. It is not a general merge that waits only for the selected branch.

**User request:** Explain task skipping.

**Explanation:** If an archive task depends on both a summary and an optional plot task, skipping the plot also skips the archive even when the summary succeeds. For optional content that must rejoin, a useful pattern is a successful result explicitly stating that no plot was requested. The archive can then inspect both successful inputs. A genuinely unavailable prerequisite should instead prevent dependent work.

**Source:** [Reviewed Gust task-readiness logic](https://github.com/marciok/gust/blob/23fc8361482c2f85169c89a384d3a5ee73c2f317/apps/gust/lib/gust/dag/stage_coordinator/retrying_task.ex#L23-L64).

**User answer:** Pending clarification; no final selection yet.

**Rejected alternatives:** None yet.

### Q7 — Interrupted stages

**Question:** If the Python server crashes during a stage, may that stage restart from its beginning while completed stage outputs are reused, or must it resume from an internal checkpoint?

**Recommendation:** Reuse completed stage outputs and restart only the interrupted stage. Choose meaningful stage boundaries so the repeated work is acceptable. Add internal checkpoints only where measured duration or cost justifies them.

**Reason:** Durable workflow steps do not imply recovery of Python process memory. Internal checkpoints add algorithm-specific state, storage, compatibility, and recovery work.

**Options:**

1. Restart interrupted stage — completed outputs persist; a retried request attaches to the same logical operation or restarts it after confirmed execution loss.
2. Resume within stages — long numerical stages persist internal progress, such as completed chunks, and restore that progress after failure.

**User answer:** Restart interrupted stage.

**Accepted recovery, refined by Q10:** Gust persists completed successful task results and reuses them. Only the interrupted stage restarts with the same inputs and seed policy. With a compute-only Python server there is no operation lookup after a timeout; retry may repeat computation. That is allowed, provided the scientific result and logical effects are idempotent.

**Not required initially:** Internal checkpoints within numerical stages. Revisit only if measured restart cost justifies them.

### Q8 — Deployment versions

**Question:** Must an active study survive code deployments using its original graph and stage versions, or may deployments require active studies to finish or be cancelled first?

**Recommendation:** Pin the executable graph, stage implementations, environment, and input contracts for each study execution. New runs use new versions; existing runs keep their pinned versions. If a required version is unavailable, stop explicitly rather than silently substitute new code.

**Reason:** Reusing completed artifacts while changing an unfinished stage can mix incompatible methods or output schemas. A source hash identifies the intended code but does not preserve a runnable copy.

**Options:**

1. Resume pinned versions — retain compatible executors and artifacts for active executions across deployments.
2. Drain before upgrades — allow crash recovery within the same deployment version, but require active studies to finish or be cancelled before incompatible code updates.

**User answer, summarized:** Do not worry about full versioning now; this is a prototype. Forking Gust to implement versioning could be considered later.

**Decision:** Defer automatic cross-deployment compatibility and old-executor retention. Neither production-grade version pinning nor an enforced draining system is an initial prototype requirement. Keep basic provenance and avoid promising that runs survive incompatible code changes.

**Preserved requirement:** Crash recovery with unchanged code and environment, persisted completed outputs, and restart of interrupted stages.

**Fork status:** Possible future option only. No fork or versioning implementation is requested.

**Rejected direction:** Making production deployment-version management a prerequisite for evaluating the prototype.

## Verification

### F4 — Statistical invariants

Observed: crossed resampling uses plan rows and shared attack columns. Deterministic seed derivation and correction order affect results.

Relevant files:

- `evaluation/analysis/src/network_defense_analysis/statistics.py:79-125`, `:165-231`, `:256-284`
- `evaluation/analysis/src/network_defense_analysis/report.py:398-401`
- `evaluation/analysis/src/network_defense_analysis/study.py:287-290`

Preserving output field names alone does not prove statistical equivalence. Check normalization, comparison ordering, attack alignment, seed derivation, and multiple-test correction.

### F5 — Safety invariants

Observed: archive handling checks paths, symlinks, members, uncompressed sizes, and checksum coverage. HTTP handling checks content type, request limits, and available analysis slots.

Relevant files:

- `evaluation/analysis/src/network_defense_analysis/archive.py:11-99`
- `evaluation/analysis/src/network_defense_analysis/service.py:97-143`

Q11 removes archive handling, so archive-only checks leave the target with it. Keep appropriate JSON content-type, request-size, and compute-capacity limits. A schema library does not replace those HTTP/runtime limits.

### Regression evidence

Pending. Select small deterministic fixtures and typed-contract tests before implementation. Compare numerical results, seed behavior, family membership, and dashboard data meaning. Legacy ZIP bytes, file members, and CSV layouts are not compatibility targets after Q11. Preserve scientific ordering and deterministic behavior where required.

### Migration sequence

Pending. Choose changes after the scope and compatibility decisions. This review did not run tests, benchmarks, or evaluation jobs.

## Related documents

- [Evaluation concepts](../concepts/evaluation.md)
- [Analysis package](../../evaluation/analysis/README.md)
- [Cloud tooling plan](cloud-evaluation-tooling-plan.md)
- [Topology-scale study](topology-scale-study.md)
