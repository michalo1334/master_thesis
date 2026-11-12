# Study UI integration plan

Updated: 2026-11-12.

Baseline: native Study UI commit `b2f58b4`.
The [minimal identity amendment](#amendment-automatic-identifiers-and-optional-study-name) defines the implemented follow-up scope and replaces the earlier expanded proposal.

The cleanup in [Legacy retirement](#legacy-retirement) remains complete.
Proposed function, type and file names can change during implementation. Their responsibilities and the agreed behavior remain fixed.

## Agreed scope

| Decision | Selected behavior |
|---|---|
| Workflow | Full cycle: define a revision, run Pilot, review, approve Final, continue execution and read results |
| Location | New Study document type in the existing dashboard workspace |
| Document identity | One document per revision, containing its execution history and selected execution |
| Authoring | Structured settings, optional Study name and automatically supplied Study/Family IDs |
| Revision number | Retain the existing explicit revision-number input |
| YAML | Generated, read-only view with copy/download; no YAML import or two-way editing |
| Progression | Manual Continue; no background study coordinator |
| Components | Reuse existing components; add missing reusable controls to the UI kit |
| Notifications | In-app progress, persistent milestone/error notices, status messages and document attention indicators |
| Existing tools | Preserve graph editing, graph comparison, standalone simulation and standalone optimization |
| Evaluation boundary | Keep native Evaluation2 as the only evaluation pipeline |

Implementation defaults proposed for the first version:

- Restore unfinished forms through existing workspace persistence. Server-side draft storage is outside this version.
- Keep study controls inside the document. Preserve the current graph/simulation/optimization ribbon.
- Use existing storage and the existing YAML serializer.
- Keep notification history in the client session. Stored execution state supplies the facts needed after reconnect.

## Amendment: automatic identifiers and optional Study name

Remove the **Study ID** and **Family ID** controls. Add an optional **Study name**.
Keep the revision-number input and scientific settings unchanged.

### Smallest implementation

1. **Reuse the options request.** Send the existing workspace document UUID with `fetch_study_options`. Elixir derives stable default Study/Family IDs from it and returns them with the options. Fill only blank draft IDs. Existing persistence keeps them stable across reload; YAML and Freeze use the same values.
2. **Use the existing definition JSON for the name.** Add a nullable name to the study declaration and current projections/contracts. The codec already supports missing nullable/default fields. Normalize blank names to absent in the backend. Show the name in titles and the picker, with Study ID as fallback; include it in YAML and the existing search query.
3. **Reuse creation and cloning.** Keep the existing Freeze request, shared constructor, Study ID/revision uniqueness and conflict handling. Cloning keeps its current IDs and copies the name; the user enters the new revision number.

```text
Document UUID -> existing options request -> default IDs
Draft fields + optional name -> existing Freeze -> saved definition
```

Preserve saved IDs, existing draft fields, lazy recovery, lost-reply feedback and request guards.
A missing name means unnamed. Names leave scientific seeds, comparison membership and inference unchanged.

**Excluded:** new endpoints, authoring-key storage, database columns/indexes, snapshot versions, recovery state machines and automatic save retries.
If existing JSON storage cannot support the change, stop and explain the blocker before expanding scope.

### Verification

Update the existing backend authoring test and rendered form test for stable IDs, optional-name round-trip and removed controls.
Reuse existing clone/recovery coverage; add a missing-name compatibility assertion only if needed.
Run the focused Study frontend tests and `mix precommit` once after implementation.
Skip new test suites, fault-injection matrices, full browser lifecycle journeys and recalibration.

## Initial implementation baseline

This table records the starting state of the original integration work.

The supported facade is [`NetworkDefense.Evaluation2.Study`](../../src/lib/network_defense/evaluation2/study.ex).
The [study overview](../concepts/evaluation-study-overview.md), [operator guide](../evaluation2.md) and
[pipeline guide](evaluation-study-pipeline.md) describe its current behavior.

| Surface | Current state |
|---|---|
| Revision creation | YAML parsing, declaration validation, graph/Host resolution and immutable persistence |
| Execution | Start, Continue, status, Pilot report, Final approval, cancellation and stored Final result |
| Lifecycle | Durable state and canonical phase/run ownership |
| Collection | Shared optimization/simulation effects; sequential Final tiers; excluded warm-up and five measured replicas per tier |
| Analysis | Native Pilot assessment and Final statistics with family correction |
| Browser | Graph, simulation and optimization documents, reports, catalog and Runs view |
| Missing study reads | Public revision listing/detail, execution listing and progress snapshot |
| Missing browser integration | Study document, study web contracts, commands, event routing and views |

Existing progress mechanisms are relevant to this work:

- Optimization callbacks report completed steps, total steps and activity detail. The optimization context already publishes these updates.
- `Simulations.run/2` accepts `on_progress` and optional event publication. Native study collection currently supplies only correlation identity.
- Gust publishes task/run lifecycle changes and stores their statuses.
- Report generators have separate assembly-progress callbacks. Those counters describe report loading, rather than scientific execution.
- The dashboard already forwards optimization/simulation events and renders `ReportProgress`.
- Report documents have unread state. The shared workspace tab dot currently needs state binding to show document attention.

## Workflow and ownership

```text
Editable draft
    |
    | Freeze revision: authoritative backend validation
    v
Frozen revision
    |
    | Start new Pilot
    v
Pilot collection --Continue--> Pilot analysis
                                    |
                                    v
                              Awaiting Final
                                    |
                         Explicit Final approval
                                    |
                                    v
Final collection --Continue--> Final analysis --> Stored result

Active execution / Awaiting Final --> Cancelled
Active execution                 --> Failed
```

Continue can advance across phases and tiers until approval, a terminal state, a finite timeout or an error.
The arrows above mark user-controlled progression, rather than a required click for every phase.
Start ensures the first Pilot run. Approval ensures the first Final tier run. Both return before the full workflow finishes.

Elixir owns validation, candidate selection rules, accepted lifecycle state, collection proof, inference and measured timing.
Svelte owns editable fields, document selection, generated YAML, presentation and transient request state.

### Continue request lifetime

Use a LiveView-owned asynchronous task for each explicitly requested continuation.
The event handler acknowledges the request promptly, so progress and cancellation remain available.

| Event | Behavior |
|---|---|
| Select Continue | Start one continuation request for that execution in this LiveView |
| Switch workspace tabs or selected execution | Keep the request active; route updates to its execution model |
| Close the Study document | End its continuation callers and observation subscriptions; leave dispatched work under existing backend rules |
| Lose the LiveView connection | End its continuation callers with the owning LiveView |
| Return at a finite timeout | Clear the pending request, refresh status and offer Continue when applicable |
| Reopen/reconnect | Reload accepted status and progress; require another explicit Continue to advance |
| Cancel execution | Use `Study.cancel/1`; clear active request state after reconciliation |

Ending a continuation caller is separate from cancelling the execution.
Dispatched work can finish after its caller ends. A later Continue can accept completed work and advance it.
Existing clock-loss limits remain: an interrupted incomplete measured session cannot supply replacement timing.

Observation only reads state and forwards notifications. It never starts, approves or advances an execution.
Watchers belong to the open document models, rather than mounted view components, so tab switching preserves observation.

## Interface

The diagrams are schematic. `<...>` marks a value or placeholder, rather than a scientific default.

### Workspace and opening

```text
+----------------------------------------------------------------------------------------------+
| Network Defense                                                                              |
+----------------------------------------------------------------------------------------------+
| Home | Simulation | Optimization                                                             |
+----------------------------------------------------------------------------------------------+
| DOCUMENTS             | Topology x | Report x | Study: <name> r<N> x | +                       |
|                       +--------------------------------------------------+-------------------+
| Graphs                |                                                  | INSPECTOR         |
|   <small graph>       |                                                  |                   |
|   <medium graph>      |                 STUDY DOCUMENT                   | Revision context  |
|   <large graph>       |                                                  |                   |
|                       |        Definition, executions and results        | Selected execution|
| Open documents        |                                                  |                   |
| > Study: <name> r<N>   |                                                  | Selected-row      |
|                       |                                                  | details           |
+-----------------------+--------------------------------------------------+-------------------+
| Study: <name> r<N>                                                <operation / connection>   |
+----------------------------------------------------------------------------------------------+

+ menu -> Study

              +---------------------------------------------------------------+
              | Studies                                                   [x] |
              | Search [....................................................] |
              |                                                               |
              | Study             Revision   Executions   Latest state        |
              | ------------------------------------------------------------- |
              | <study>           <N>        <count>      Awaiting Final       |
              | <study>           <N>        <count>      Succeeded            |
              | <study>           <N>        <count>      No executions        |
              |                                                               |
              | [New study revision]                        [Open selected]   |
              +---------------------------------------------------------------+
```

Opening a revision already present in the workspace selects its existing tab.
The inspector supplies context and selected-row details. Scientific inputs remain in the main definition form.

### Definition editor

```text
+----------------------------------------------------------------------------------------------+
| Study: <name>                                                                   DRAFT        |
| [Definition*] [Executions: 0]                                             [Freeze revision]   |
+------------------------------------------------------------+---------------------------------+
| FORM                                                       | GENERATED YAML                  |
|                                                            | Read-only         [Copy] [Save] |
| IDENTITY                                                   | ------------------------------- |
| Study name (optional) [..................................] | <serialized authored fields>    |
| Revision          [........]                               |                                 |
| Master seed       [......................................] | Updates from the form.          |
|                                                            |                                 |
| ANALYSIS                                                   |                                 |
| Family alpha      [........]                               |                                 |
| Confidence level  [........]                               |                                 |
|                                                            |                                 |
| DEFENSE POLICY                                             |                                 |
| Feasibility       [Required                            v]  |                                 |
| Allowed actions   [Choose actions...]                       |                                 |
|                                                            |                                 |
| SIMULATION                                                 |                                 |
| Iterations/run    [........]  Maximum attempts [........]   |                                 |
| Rules             [Choose rules...]                        |                                 |
|                                                            |                                 |
| TIERS                                                      |                                 |
| [Small*] [Medium] [Large]                                   |                                 |
| Graph             [<saved graph>                       v]  |                                 |
| Graph revision    [<saved revision>                    v]  |                                 |
| Foothold Host     [<Host from this revision>           v]  |                                 |
|                                            [Open graph]    |                                 |
| Budgets           [<budget>] [<budget>] [+ Add budget]      |                                 |
|                                                            |                                 |
| Alternative          Objective          Scoring trials     |                                 |
| ---------------------------------------------------------- |                                 |
| <strategy>           <if required>       <if required>       |                                 |
| [+ Add alternative]                                        |                                 |
| Reference: CVSS using each declared budget                  |                                 |
|                                                            |                                 |
| PILOT CANDIDATES                                           |                                 |
| ID                  Plans/side          Attacks/plan        |                                 |
| [................]  [............]      [............] [x]  |                                 |
| [+ Add candidate]                                          |                                 |
|                                                            |                                 |
| Extra pool: plans [........]  attacks [........]             |                                 |
| Outer subsamples  [........]                               |                                 |
| Target half-width [........]  Guard quantile [........]     |                                 |
|                                                            |                                 |
| FINAL PROTOCOL                                             |                                 |
| Small -> Medium -> Large                                   |                                 |
| Per tier: excluded warm-up + five measured replicas         |                                 |
|                                                            |                                 |
| RUNTIME CONTEXT                                            |                                 |
| Measurement label: <configured label / unavailable>         |                                 |
+------------------------------------------------------------+---------------------------------+
| <validation summary or submission error>                                  [Freeze revision]   |
+----------------------------------------------------------------------------------------------+
```

Form behavior:

- A graph revision constrains foothold selection to its Hosts. Reuse the existing graph read/picker path.
- Each tier has independent budgets and alternatives. Scoring fields appear only for strategies that require them.
- Scientific defaults must be explicit. The illustrative YAML template is not a source of recommended research settings.
- Study name is optional. IDs are supplied once through the existing options load and stay out of editable controls.
- Freeze sends unchanged form text to the backend. The web boundary casts numeric fields and returns field-path errors; the shared definition constructor validates scientific settings.
- Preserve backend issue paths when available. General constructor errors appear in the form summary.
- Changing the form regenerates YAML. Preserve seed precision during scalar conversion.
- Warn before discarding an unfinished draft.

### Frozen definition

```text
+----------------------------------------------------------------------------------------------+
| Study: <name> / Revision <N>                                                    FROZEN        |
| [Definition*] [Executions: <count>]                            [Create revision from this]    |
+----------------------------------------------------------------------------------------------+
| Identity, seed, family, alpha, confidence and frozen measurement label                        |
|                                                                                              |
| Tier      Graph revision          Foothold          Budgets          Alternatives             |
| -------------------------------------------------------------------------------------------- |
| Small     <graph / revision>      <Host>            <budgets>        <strategies>              |
| Medium    <graph / revision>      <Host>            <budgets>        <strategies>              |
| Large     <graph / revision>      <Host>            <budgets>        <strategies>              |
|                                                                                              |
| [v] Defense and simulation settings                                                           |
| [v] Pilot candidates and precision settings                                                    |
| [v] Derived study structure                                                                    |
| [v] Generated YAML                                                           [Copy] [Save]   |
+----------------------------------------------------------------------------------------------+
```

The frozen view comes from the saved typed definition. The backend does not retain original YAML text.
Create revision from this copies settings, existing IDs and the optional name into a new draft. The user supplies and confirms the new revision number.

### Execution history and status

```text
+----------------------------------------------------------------------------------------------+
| Study: <name> / Revision <N>                                                    FROZEN        |
| [Definition] [Executions*: <count>]                                        [Start new Pilot]  |
+----------------------------------------------------------------------------------------------+
| EXECUTIONS                                                                       [Refresh]  |
| Execution       Started         State                Pilot outcome       Final selection     |
| -------------------------------------------------------------------------------------------- |
| <A>             <date/time>    Succeeded            Recommended         <candidate>          |
| <B>             <date/time>    Awaiting Final       Insufficient        --                   |
| > <C>           <date/time>    Collecting Final     Recommended         <candidate>          |
+----------------------------------------------------------------------------------------------+
| EXECUTION <C>                                                                                |
| [Status*] [Pilot] [Results: unavailable]                                                       |
|                                                                                              |
| [done] Pilot collection -> [done] Pilot analysis -> [done] Approval                            |
| [active] Final collection -> [ ] Final analysis -> [ ] Complete                               |
|                                                                                              |
| Tier: <tier>                       Measured replica: <position> of 5                          |
| Optimization items [================..........] <completed> / <total>                        |
| Simulation trials  [==========................] <completed> / <total>                        |
| Activity: <operation detail>                                                                  |
|                                                                                              |
| [Continue] [Refresh status]                                             [Cancel execution]   |
+----------------------------------------------------------------------------------------------+
```

Disable Continue while the same execution has an active continuation request in this LiveView.
Use explicit warm-up labeling before measured replicas. Show unknown totals with the existing waiting indicator.
The two bars represent their named units. They do not estimate whole-study completion time.

### Pilot review and approval

```text
+----------------------------------------------------------------------------------------------+
| EXECUTION <B>                                                            AWAITING FINAL      |
| [Status] [Pilot*] [Results: unavailable]                                                      |
+----------------------------------------------------------------------------------------------+
| Outcome: <recommended / insufficient>                                                       |
|                                                                                              |
| Candidate     Plans/side  Attacks/plan  Predicted time  Worst guarded half-width  Pass         |
| -------------------------------------------------------------------------------------------- |
| <candidate>   <count>     <count>       <duration>      <value>                   <yes/no>     |
| > <candidate> <count>     <count>       <duration>      <value>                   <yes/no>     |
|                                                                                              |
| SELECTED CANDIDATE DETAILS                                                                    |
| Tier    Budget    Alternative vs CVSS    Guarded half-width    Informative    Pass            |
| -------------------------------------------------------------------------------------------- |
| <tier>  <budget>  <strategy>             <value>               <yes/no>       <yes/no>        |
|                                                                                              |
| Recommended:                                                                                 |
| [Approve recommended candidate]                                                              |
|                                                                                              |
| Insufficient:                                                                                |
| Candidate [<declared candidate> v]                                                            |
| [ ] I accept proceeding without meeting the Pilot precision target.                          |
| [Approve insufficient override]                                                              |
|                                                                         [Cancel execution]   |
+----------------------------------------------------------------------------------------------+
```

Render only the approval area allowed by the accepted outcome.
A recommendation approves the recommended candidate. An insufficient override selects an existing declared candidate.
Approval freezes its exact counts. The confirmation checkbox is a UI safeguard, rather than a new scientific setting.
Pilot precision remains a planning assessment; fresh Final precision can differ.

### Final results

```text
+----------------------------------------------------------------------------------------------+
| EXECUTION <A>                                                                  SUCCEEDED     |
| [Status] [Pilot] [Results*]                                                                  |
+----------------------------------------------------------------------------------------------+
| Candidate: <ID>    Plans/side: <count>    Attacks/plan: <count>                               |
| Pilot outcome and approval: <accepted context>                                               |
|                                                                                              |
| [Comparisons*] [Timing]                                                                       |
| Tier [All v]    Budget [All v]    Alternative [All v]                                         |
|                                                                                              |
| Tier   Budget  Alternative  Estimate  Pointwise interval   Raw p  Holm p  Reject              |
| -------------------------------------------------------------------------------------------- |
| <tier> <value> <strategy>   <delta>   [<lower>, <upper>]    <p>    <p>     <yes/no>            |
|                                                                                              |
| Selected comparison: estimate, interval, test, family decision, assessment and warnings      |
| Negative mission-impact differences favor the alternative.                                  |
| Family decisions use Holm-adjusted p-values.                                                 |
+----------------------------------------------------------------------------------------------+

+----------------------------------------------------------------------------------------------+
| [Comparisons] [Timing*]                                                                      |
| Tier [Small*] [Medium] [Large]                                     Display units [Seconds v] |
|                                                                                              |
| Boundary                   Median                   Minimum                  Maximum        |
| -------------------------------------------------------------------------------------------- |
| Plan selection             <duration>               <duration>               <duration>     |
| Simulation                 <duration>               <duration>               <duration>     |
| Total                      <duration>               <duration>               <duration>     |
|                                                                                              |
| Replica                    Plan selection           Simulation               Total          |
| -------------------------------------------------------------------------------------------- |
| 1                          <duration>               <duration>               <duration>     |
| 2                          <duration>               <duration>               <duration>     |
| 3                          <duration>               <duration>               <duration>     |
| 4                          <duration>               <duration>               <duration>     |
| 5                          <duration>               <duration>               <duration>     |
|                                                                                              |
| Warm-up is excluded. Total covers measured plan selection and simulation.                    |
| Later statistical analysis lies outside these measured intervals.                            |
+----------------------------------------------------------------------------------------------+
```

Use the stored public result and existing Pilot/timing helpers for derived summaries.
Svelte filters and formats values. It does not rerun inference, candidate selection or family correction.

### Interrupted and terminal states

| State | Display and actions |
|---|---|
| Continue request ended while execution remains active | Accepted state, progress snapshot, Refresh, Continue and Cancel |
| Failed | Failed phase, bounded error code/message, retained accepted context, View definition and Start new execution |
| Cancelled | Cancellation state, retained accepted context, View definition and Start new execution |
| Result unavailable | Current lifecycle state and the supported unavailable error; no partial Final result |

A new execution is a separate attempt. Preserve existing failure, cancellation and clock-loss rules.
Underlying effects can finish after best-effort cancellation; late work cannot advance the terminal execution.

## Elixir public interfaces

### Retained operations

| Operation | UI responsibility |
|---|---|
| `create_revision/1` | Existing YAML caller support |
| `start/1` | Commit an execution and ensure its first Pilot run |
| `continue/2` | Caller-owned progression |
| `status/1` | Read accepted lifecycle state |
| `pilot_result/1` | Read the accepted complete candidate report |
| `resume/2` | Approve `:recommended` or `{:override_insufficient, candidate_id}` |
| `cancel/1` | Commit cancellation before best-effort stopping |
| `result/1` | Read the successful stored result |

### Proposed additions

| Operation | Public value | Purpose |
|---|---|---|
| `definition_options/0` | `DefinitionOptions` | Registered actions, rules, alternatives, objectives and scoring requirements; relevant runtime context |
| `create_revision_from_params/1` | `Revision` | Freeze structured authored input |
| `list_revisions/1` | Bounded page of `RevisionSummary` | Search/open saved revisions |
| `get_revision/1` | `RevisionDetail` | Read authored settings, frozen context and derived summary |
| `list_executions/2` | Bounded page of `ExecutionSummary` | Read one revision's execution history |
| `progress/1` | `ProgressSnapshot` | Reconstruct execution scope and work counters |

Keep `{:ok, value}` / `{:error, Study.Error}` responses.
List queries use server-enforced bounds and stable ordering. List summaries avoid loading full reports and collection matrices.
Missing revisions remain distinguishable from an existing revision with no executions.

Public values expose declared revision identity and execution IDs.
Private persistence rows, phase links, Gust IDs, effect links and clock sessions remain server-side.
Existing `Status` and `Result` semantics remain intact; richer browsing values are separate types.

### One construction path

```text
Existing YAML input                  Structured form input
       |                                      |
Decode document                       Decode wire values
       |                                      |
       +------------------+-------------------+
                          |
                 Definition.parse
                          |
                 Definition.resolve
                          |
                 Revision insertion
```

Refactor YAML creation to delegate to the same construction path as structured creation.
The authored input shape contains declared settings. Derived scientific values and provenance come from Elixir.
A revision-detail projection recovers this authored shape from the saved definition, with frozen context reported separately.

### Elixir code map

Paths below are relative to `src/lib/`.

| Location | Planned change |
|---|---|
| `network_defense/evaluation2/study.ex` | Public authoring/read operations and the shared YAML/structured construction entry point |
| `network_defense/evaluation2/study/definition.ex` | Shared construction and projection back into authored settings |
| `network_defense/evaluation2/study/persistence.ex` | Bounded revision/execution queries using existing storage |
| `network_defense/evaluation2/study/views.ex` | Revision detail, list summaries and public-value mapping |
| New public view modules under `network_defense/evaluation2/study/` | Typed options, detail, summary and progress values |
| New `network_defense/evaluation2/study/progress.ex` | Canonical source-event mapping and reconstructed progress snapshots |
| `network_defense/evaluation2/study/collection.ex` | Connect existing effect progress to study observation |
| `network_defense/optimizations.ex` and `network_defense/simulations.ex` | Reuse supported callbacks/publication; add forwarding only where required |
| Lifecycle acceptance/provisioning boundaries | Publish state/link notifications after successful commits where required |
| `network_defense_web/live/web/dashboard/dashboard_live.ex` | Study request dispatch, async continuation and outgoing event routing |
| New focused modules under `network_defense_web/` | Study web mapping, observation subscriptions and session cleanup |

Keep lifecycle acceptance, completion proof and timing owners unchanged.
No direct phase dispatch or persistence-row access is added to Svelte.

## Web contracts and request handling

Add contracts under `src/lib/network_defense_web/contracts/dashboard/study/`.
Use `mix gen.contracts` to generate `src/assets/svelte/contracts.generated/dashboard/study.ts`.
Svelte imports generated wire types. Local incomplete form state can use a separate editing model.

| Request group | Proposed request names |
|---|---|
| Authoring | `fetch_study_options`, `create_study_revision` |
| Browsing | `fetch_study_revisions`, `fetch_study_revision`, `fetch_study_executions` |
| Execution | `start_study_execution`, `continue_study_execution`, `approve_study_final`, `cancel_study_execution` |
| Reads | `fetch_study_status`, `fetch_study_pilot_result`, `fetch_study_result` |
| Observation | `watch_study_execution`, `unwatch_study_execution` |
| Document lifetime | `close_study_document`: release this document's observers and continuation callers |

The document-lifetime request is session cleanup. It does not mutate the study lifecycle.
Continue receives an immediate accepted/rejected acknowledgement with request identity.
Its later completion reports the current status or bounded error, including a finite-timeout return.

| Outgoing event | Meaning |
|---|---|
| `study_execution_updated` | Refreshed accepted lifecycle state |
| `study_progress` | Scoped counters and activity |
| `study_continue_finished` | The explicitly requested continuation returned |

Wire requirements:

- Include execution identity on execution events. Include watch identity and presentation sequence on observed updates.
- Carry master seeds as decimal strings across the browser boundary. Decode them to exact integers before domain construction.
- Generate YAML seeds from an exact representation, rather than a JavaScript `Number` outside its safe range.
- Preserve public estimates and p-values. Round only for display.
- Preserve error category, issue code, path and message. General validation errors remain valid form-level feedback.
- Bound request sizes and list parameters at the web boundary. Freeze still validates the full scientific contract.
- Preserve a returned execution ID even if initial provisioning needs retry. Continue re-enters that committed execution.
- Keep Start distinct from Continue. Start creates another execution, so an uncertain Start reply requires history reconciliation before retry.

Keep `DashboardLive` as the entry point. Put study request mapping and observation logic in focused modules to limit handler growth.

## Callback-based progress and notifications

### Sources and adapter

```text
Optimization callback -> Existing progress events --+
                                                    |
Simulation callback  -> Existing progress events ----+--> Study progress adapter
                                                    |          |
Gust task/run events -------------------------------+          |
                                                               v
                                                      Typed LiveView events
                                                               |
                                                               v
                                                      Study execution model
                                                               |
                                                               v
                                                      Existing progress UI

Durable study/effect/task records -> Progress snapshot on open, reconnect and reconciliation
```

Reuse the optimization publication path first.
Enable the existing simulation publication path for study effects, or forward its supported callback through the same study adapter.
Add optimization callback forwarding only if existing event publication cannot supply the required context.
Callbacks remain local to executing workers. Stored DAG inputs contain identities and data, rather than browser callback functions.

The study progress implementation owns canonical item/phase resolution.
The web observer owns subscriptions and transport. It reads or forwards state without dispatching or accepting work.
Lifecycle transition events must follow committed acceptance. Add a narrow post-commit notification where existing signals do not cover that boundary.
Refresh canonical subscriptions as new phase/tier runs become linked.

### Snapshot and counter rules

A progress snapshot contains:

- Execution identity and accepted status.
- Current phase, tier and replica scope, including an explicit warm-up marker.
- Named counters with completed, total and unit fields; unknown totals remain explicit.
- Activity details for active work when available.

Resolve callback correlation through the collection item and its canonical ownership.
Graph identity alone cannot distinguish executions, replicas or repeated effects.

Count rules:

1. Replace an operation's latest counter; do not add each callback message to the aggregate.
2. Deduplicate by canonical work identity and effect stage. Reconcile retry/attempt changes with durable task/effect state.
3. Use stored completion/status for completed work. Budget-step callbacks alone cannot prove optimization completion.
4. Keep optimization items, simulation trials and analysis jobs as distinct units.
5. Treat Gust completion as a refresh signal. Accepted Study state determines Pilot availability and Final success.
6. Keep observed progress separate from measured timing. Timing displays use accepted duration receipts.

Subscribe before snapshot reconciliation. Reject stale watch identities and out-of-order presentation updates.
After open/reconnect, rebuild counters from durable records and overlay current live activity.
Use bounded read-only reconciliation for missed events; reconnect never invokes Continue.

Callbacks publish lightweight signals. Aggregate and throttle frequent updates before browser delivery.
Important lifecycle milestones are delivered promptly.
The UI publication adapter must isolate notification errors from computation. Preserve existing callback control/error semantics outside this adapter.

### Notification policy

| Event | UI response |
|---|---|
| Work counter/activity | Update scoped progress and detail text |
| Retry | Show retry status inline |
| Accepted Pilot awaiting approval | Persistent approval notice; mark execution and background Study document for attention |
| Accepted Final success | Completion notice; mark unread result |
| Accepted failure | Persistent bounded error notice; mark execution/document for attention |
| Cancellation | Show cancelled state and reconcile pending requests |

Track attention per execution and aggregate it at the Study tab.
Clear an execution's attention when the user reviews that execution.
Reuse the report unread-state pattern and connect the shared tab indicator to generic document state.
Do not force Study documents into the single-report state model.

Use the existing status bar for concise operation feedback.
Milestones and errors remain visible in the execution view, so another status message cannot hide the required action.
Use accessible status/live-region patterns, with throttled announcements for frequent progress.

The first version uses in-app notices. Reconnect restores current facts without replaying every historical completion alert.
A toast service, desktop push and durable notification records remain outside this version.

## Svelte models and component changes

Proposed study area:

```text
src/assets/svelte/dashboard/study/
  StudyDocument.svelte.ts
  StudyDefinitionModel.svelte.ts
  StudyExecutionModel.svelte.ts
  Study.svelte
  definition/...
  execution/...
  pilot/...
  results/...
```

| Model | Responsibility |
|---|---|
| `StudyDocument` | Revision/draft identity, internal tabs, execution history, selected execution and workspace recovery |
| `StudyDefinitionModel` | Editable fields, generated YAML, raw form transport and backend validation feedback |
| `StudyExecutionModel` | Accepted status, scoped progress, Pilot/result values, pending commands and attention state |

One Study document contains several execution models.
Request and observation state belongs to these models, so switching rendered views preserves the active work context.

| Existing integration point | Change |
|---|---|
| `dashboard-api.ts` | Typed study request methods |
| `DashboardHost.svelte` | Study event listeners and routing entry point |
| `DashboardModel.svelte.ts` | Route by document/execution/watch identity; coordinate command and document lifetime |
| `WorkspaceDocument.svelte.ts` | Study document union member |
| `workspace/dashboard-registry.ts` | Create, render and recover Study documents |
| `workspace/WorkspaceModel.svelte.ts` | Open/select revisions; prevent duplicate tabs; close/recovery integration |
| Inspector registry | Study context and selected-row perspectives |
| Shared workspace tab model/view | Generic attention state and indicator |

Persist authored draft fields and view selection through existing workspace persistence.
For frozen documents, persist revision reference, selected execution and view selection.
Reload accepted status, progress and reports from Elixir. Cached progress and pending command flags are not authoritative after recovery.

### Component reuse

| Need | Reuse |
|---|---|
| Document shell and navigation | `Workspace`, `DocumentOutline`, document registry |
| Revision/execution/candidate/result tables | `FilterableTable` |
| Graph/revision selection | `GraphTreePickerDialog` |
| Host selection | `Select` with Hosts from the selected revision |
| Counts, numeric fields and policies | Existing `NumberInput`, `Select`, `Checkbox` where their value semantics fit |
| Option selection | `OptionPickerDialog`, existing Bits UI dialogs |
| Internal tabs | Existing Bits UI tabs |
| Context panel | `Inspector`, `InspectorField` |
| Live progress | `ReportProgress`; generalize into the UI kit if needed for shared use |
| Operation feedback | `StatusBar` and existing accessible inline patterns |

Create study-specific composition for definition editing, tier settings, execution history, Pilot approval and Final reports.
Place missing reusable controls in the UI kit, with focused tests and existing design tokens.
Candidate gaps include exact string-based input, a shared status notice and a step indicator.
Confirm each gap before adding a component. Reuse existing controls where they satisfy semantics and accessibility.

## Implementation sequence

| Phase | Work | Completion evidence |
|---|---|---|
| P1: Reads and contracts | Revision/execution queries, public views, progress snapshot, authoring options, wire contracts and generated types | Bounded reads work; absent and empty cases differ; wire values preserve identity and numeric precision |
| P2: Definition document | Registry integration, new/open picker, form, generated YAML, shared constructor, freeze and frozen detail | Form-created revision reloads correctly; equivalent YAML/structured input freezes equal definitions; draft recovery works |
| P3: Execution and progress | Start, LiveView-owned Continue, approval, cancellation, callback/Gust observation, notices and attention | Recommended and insufficient journeys work; progress routes correctly; document closure/reconnect preserve manual progression rules |
| P4: Results and recovery | Comparison/timing views, inspector context, completed/failed/cancelled recovery | Stored results and all measured timings display correctly; errors and accepted context remain visible |
| P5: Integrated verification | Focused automated checks, safe manual journey and retained workflow regression | Required behavior, `mix precommit` and `npm test` pass; verification limits and any blockers are recorded |

P1 precedes P2/P3. P4 builds on the execution model. Each phase keeps the existing supported workflows usable.

## Execution goal

The [Pi execution goal](../inprogress/evaluation-study-ui-goal.txt) converts this plan into one pasteable `/goal` command.
It describes the original P1-P5 work. Update the saved command to the smaller identity-amendment scope before using it for that work. Saving the command does not activate goal mode.

| Goal part | Contract |
|---|---|
| Outcome | Working Study document covering authoring, execution, approval, progress and stored results |
| Verification | Focused backend/frontend tests, full checks, ExDNA review and isolated browser journey with artifacts |
| Constraints | Existing scientific/lifecycle rules, component reuse, manual Continue and retained standalone tools |
| Boundaries | Focused application/tests/documentation; preserve data, infrastructure and existing work |
| Iteration | Follow unmet criteria in dependency order; fix scoped failures and recheck affected behavior |
| Blocked stop | Report verified work, attempted paths, exact blocker, uncertainty and next input |

## Verification

For the identity amendment, use its focused verification above plus normal precommit checks.
The requirements below describe the original full integration; repeat additional checks only for behavior affected by the change.

Use focused checks for distinct risks:

- Constructor parity, graph/Host validation, immutable revision conflict behavior and authored-shape projection.
- Bounded listing, stable ordering, revision isolation, absent/empty reads and report availability.
- Large seed round-trip through form, wire, YAML serialization, backend construction and reload.
- Generated contract compatibility, structured errors and display-only numeric formatting.
- Recommended approval, insufficient override, invalid approval, cancellation and accepted-state gating.
- Async Continue acknowledgement, finite timeout, tab switching, document closure, disconnect and explicit re-entry.
- Multiple executions using the same graphs; concurrent items, duplicates, retries, stale subscriptions and delayed events.
- Snapshot reconciliation after missed updates; no automatic Start or Continue during recovery.
- Notification isolation from scientific work and lightweight progress publication during measured collection.
- Per-execution attention, background document markers, accessible feedback and reuse of shared components.
- Stored comparison statistics, pointwise intervals, Holm decisions, warnings and complete per-tier timing displays.
- Retained graph, simulation, optimization, reports and workspace recovery behavior.

Use a safe local manual journey for the integrated workflow and meaningful progress/notification behavior.
Confirm runtime readiness before dispatch: intended Repo targets, execution-capable Gust role, executor and truthful stable measurement label.
A successful constructor alone does not prove Final runtime readiness.

Use fresh disposable test partitions for database-backed checks. Pin both Repos to the same intended target and remove only the owned disposable database afterward.
Preserve existing development data and scientific evidence. Do not reset the environment or rerun calibration solely for UI work.
Run `mix precommit` and `npm test` from `src/` after implementation.
The frontend test suite needs its separate command; the current precommit alias covers frontend formatting, type checking and builds.
Fix scoped failures before marking a phase complete.

### Existing duplication check

Local installation check on 2026-11-07 confirmed `ex_dna` version **1.5.4**:

- The dependency is declared for development/test and resolved in the lockfile.
- Package source and compiled development/test artifacts are present.
- The `ExDNA` module loads successfully. `mix help ex_dna` exits successfully.
- `ExDNA.Credo` is enabled in `src/.credo.exs`. Strict Credo runs through `mix precommit`.

Reuse the installed check. Record baseline/post-change duplication evidence with the same scope and options when reviewing new shared logic.
Resolve newly introduced scoped duplication through suitable reuse. Preserve existing check coverage and thresholds.
Avoid new suppressions or weaker settings that conceal duplication. Keep unrelated baseline cleanup outside this goal.

## Legacy retirement

The active manifest-based evaluation pipeline was removed by commit `5c240a3`.
The native study pipeline is the retained evaluation boundary.

The follow-up cleanup in this planning session:

- Deleted the unused `src/lib/mix/tasks/evaluate/options.ex` helper and its sole test.
- Removed the helper's stale protected-path entry from the retirement inventory.
- Corrected the stale deployment-retirement sentence in [the infrastructure guide](../infrastructure.md#native-evaluation2-runtime).
- Preserved standalone tools, native storage, historical documents, deployment/build manifests and the read-only retirement audit.

Recorded cleanup verification on 2026-11-07: compilation passed; full `mix precommit` passed with **846 tests passed and two excluded**.
The owned disposable partition database was removed. The prose-only infrastructure correction passed diff/reference checks afterward.
These checks cover cleanup, rather than the planned UI implementation.

The retirement audit found no unexpected live references. Its remaining four findings concern historical `local-results` evidence files absent from this checkout.
The [verification record](../history/evaluation2-verification.md) preserves earlier scientific and retirement evidence.

## Boundaries

This work preserves the existing scientific method, explicit approval rule, canonical completion proof, measured timing protocol and terminal-state fencing.

The first version excludes:

- The retired manifest-based evaluation path and compatibility adapters.
- YAML import, editable YAML or two-way synchronization.
- An always-on study coordinator, automatic continuation on reconnect, phase replay or replacement replicas.
- Automatic recovery of a lost incomplete clock session.
- Server-side draft tables, durable notification storage, toast infrastructure or desktop push.
- New scientific defaults, inference in TypeScript or timing reconstructed from UI events.
- Infrastructure apply, deployment changes, development database resets or evidence deletion.

The existing pipeline implementation/refactor plans remain historical records.
This document is the browser-integration plan; the current dashboard guide continues to describe implemented behavior.
