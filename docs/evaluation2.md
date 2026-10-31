# Evaluation2 operator guide

Evaluation2 runs native Elixir study collection and statistical analysis.
Start with the [overview](concepts/evaluation-study-overview.md).
Read the [methodology](concepts/evaluation-methodology.md) before choosing research settings or interpreting results.

The [verification record](history/evaluation2-verification.md) preserves the verified create-to-result path.
Full calibration and removal of the legacy implementation remain later verification gates.
The commands below use the supported native facade. They have no Python analysis-service dependency.

## Runtime preparation

Run Mix commands from `src/` in the normal project environment.
Use the Elixir/OTP and dependency versions declared by the project.
Native numerics use Nx float64 and Decimal. No separate statistics server is required.

Before work starts:

1. Verify the intended local database, port and credentials for both `NetworkDefense.Repo` and `Gust.Repo`.
2. Apply application and Gust migrations to the authorized target, in that order, before seeding a fresh database.
3. Check the configured ScatterGather executor and its dependencies. The verified real studies used RabbitMQ.
4. Configure one stable `EVALUATION_MEASURED_ENVIRONMENT_REVISION` label before revision creation.
5. Use an execution-capable Gust role for Pilot, Final and continuation commands.

The existing `mix ecto.setup` alias creates, migrates both repositories, and seeds.
Use it only for an authorized new environment. Existing development data does not need a reset for study execution.
Review the alias definition before running it; `mix ecto.reset` drops data.
The [infrastructure guide](infrastructure.md#native-evaluation2-runtime) explains deployment requirements without applying infrastructure.

### Command startup roles

Every study command starts the normal application in its own VM.
It does not attach to an existing VM or use RPC.

| Commands | Startup policy |
|---|---|
| `study.pilot`, `study.final`, `study.continue` | Default to Gust `core`; preserve a declared execution-capable role |
| `study.create`, `study.status`, `study.pilot_result`, `study.result`, `study.cancel` | Force non-dispatching Gust `console` |

An execution command rejects `GUST_ROLE=console` or `web` before waiting.
Inspection does not claim unrelated queued Gust runs.
Other normal application dependencies still apply; console mode is not an offline database reader.

Keep the command VM alive while it performs measured collection.
API wait timeout leaves workers active in a live application.
Exit of the whole VM stops its workers and clock and can invalidate an incomplete timing session.

## Input contract

Copy the [illustrative YAML template](examples/evaluation2-study.yaml) to a local working file.
Replace all six graph/Host identity tokens with persisted inputs from your target environment.
The template deliberately contains no live UUIDs.
Its small counts demonstrate the protocol; they are not recommended research settings.
An unexpanded template fails UUID validation.

Use `Study.create_revision/1` or `mix study.create` as the authoritative validation path.
A generic YAML parser or JSON Schema check alone cannot prove graph membership or model feasibility.

| Input | Meaning and important constraints |
|---|---|
| `study.id`, `study.revision` | Declared identity; revision is a positive integer |
| `seed` | One integer master seed, `0 <= seed < 2^63 - 1` |
| `family.id`, `family.alpha` | Family identity and false-rejection level in `(0,1)` |
| `analysis.confidence_level` | Shared pointwise interval level for Pilot and Final, in `(0,1)` |
| `defense.allowed_action_types` | Unique nonempty list from the existing action registry |
| `defense.feasibility` | `required` by default; explicit `unrestricted` permits pre-attack infeasibility |
| `simulation` | Positive iterations/attempts and unique nonempty registered rule list |
| `tiers.small`, `.medium`, `.large` | Fixed slots; each declares graph revision, Host foothold, ordered positive budgets and alternatives |
| `pilot.candidates` | Ordered nonempty list of unique IDs and unique positive `(plans, attacks)` pairs |
| `pilot.extra_pool` | Non-negative extra plan/attack capacity |
| `pilot.precision` | Positive outer count/target half-width and guard quantile in `(0,1)` |

Each tier uses `graph_revision_id` and `foothold_node_id` directly.
The foothold must belong to that graph and have type Host.
The constructor checks required feasibility, topology-strategy prerequisites and finite positive capability weights.

Allowed alternatives are `random`, `topology_segmentation`, `simulation_informed` and `simulated_annealing`.
Scored alternatives require `scoring.objective` and positive `scoring.monte_carlo_trials`.
Objectives are `blast_radius_only`, `mission_impact_only` or `mission_then_blast_radius`.
Simple alternatives omit scoring or use null.
Every strategy inherits the shared world model and feasibility policy.
CVSS is implicit and uses the same budget as its alternatives.

The [native schema](../src/priv/evaluation2/definition.schema.json) lists required fields and registered literals.
The constructor additionally checks relationships, count limits, uniqueness, effective action policy and seed collisions.
Unknown keys are ignored and dropped. Check field spelling: an unknown key cannot override a known field.
Write each YAML key once. The YAML library resolves aliases and duplicate keys before construction; use unambiguous declarations.
There is no `schema_version`, bootstrap count, per-comparison seed list, independent CVSS configuration or empty Final block in this format.
The CLI limits the submitted document to 1 MiB.

Common constructor errors are:

| Code | Check |
|---|---|
| `invalid_yaml` | Supply one valid YAML object |
| `invalid_definition` | Check required fields, types and registered literals against the schema; this error has no field-level diagnostic |
| `invalid_graph_input` | Check the named tier's graph, Host membership, feasibility, topology prerequisites and finite capability weights |
| `duplicate_candidate` / `duplicate_candidate_counts` | Give every candidate a distinct ID and count pair |
| `unusable_action_policy` | Ensure each strategy has at least one allowed supported action type |

### Derived values

The revision stores the resolved typed definition, rather than source YAML text.
It derives these facts once:

- Pilot capacity: coordinate-wise maximum candidate counts plus extra pool;
- groups: tier, budget, CVSS then alternatives;
- comparisons: tier, budget, alternative versus CVSS;
- effective strategy action sets and inherited simulation settings;
- mission-impact bounds from graph capability weights;
- method/seed contract identities and configured measurement label.

For the template, there are nine physical groups and six comparisons.
Pilot capacity is two plans and three attacks.
Pilot therefore owns eighteen items: nine groups times two rows.
Final owns 108 items across warm-up and five measured replicas: nine groups times two rows times six replicas.
Only representative measured evidence enters inference; the other replicas do not increase sample size.

## Worked create-to-result example

This is an operator procedure with illustrative names and identity variables.
The command sequence follows the verified native executions, including their explicit insufficient override.
The guide does not copy those runs' graph UUIDs or claim that a new execution reproduces their values.

### 1. Prepare and freeze

Select graph revisions and Host nodes in your local graph workspace.
Fill the YAML tokens and choose a new study identity or revision number.
Set the stable environment label in the command environment before creation.
Keep the same label throughout collection and analysis.
Creation can freeze a missing label; Final boundaries then reject it. Constructor success alone does not prove runtime readiness.

```sh
cd src
export EVALUATION_MEASURED_ENVIRONMENT_REVISION=example-local-measurement
mix study.create ../my-study.yaml
```

Creation returns the declared study ID and revision number.
Retain them for the next command.
A different definition under an already-frozen identity returns a conflict.

### 2. Run Pilot and inspect its report

```sh
mix study.pilot example-native-study 1
# Copy the printed Execution value into EXECUTION_ID.
mix study.status "$EXECUTION_ID"
mix study.pilot_result "$EXECUTION_ID"
```

`study.pilot` prints the committed execution ID before waiting.
It drives collection and analysis to `awaiting_final` and prints the report.
Record that ID even if later provisioning or waiting fails.
The separate report command reloads the accepted complete candidate report.

Read every comparison's guarded half-width and pass decision.
The Pilot's finite-pool guard is a planning heuristic; a recommendation does not guarantee fresh-Final precision.

### 3. Approve one valid choice

Use exactly one of these alternatives, according to the accepted Pilot outcome:

```sh
# A recommended Pilot:
mix study.final "$EXECUTION_ID" --recommended

# An insufficient Pilot, with an explicit decision to give up the precision target:
mix study.final "$EXECUTION_ID" --override-insufficient demonstration
```

The override candidate must already exist in the frozen revision.
Missing, repeated or contradictory approval flags are usage errors.
An invalid approval leaves `awaiting_final` unchanged.
The Final command waits through sequential tier collection and native analysis, then prints the stored result.
It has no interactive approval prompt or command-level wait timeout.

### 4. Read and interpret

```sh
mix study.status "$EXECUTION_ID"
mix study.result "$EXECUTION_ID"
```

A successful status is `succeeded`.
The result prints every estimate, pointwise interval, raw/adjusted p-value and warning, followed by timing medians and total observed ranges.

Method labels describe different layers:

| Location | Label | Meaning |
|---|---|---|
| Frozen definition | `crossed-matching-betting-v1` | Full native numerical contract |
| Pilot report | `precision_pilot_v1` | Candidate planning report |
| Result family / command header | `holm` | Complete-family correction |
| Comparison statistics | `matching_bounded_mean_v1` | Marginal estimate and interval method |
| Comparison test | `sign_conservative_betting` | Direction-conservative marginal p-value rule |

Negative mission-impact differences favor the alternative.
Use adjusted p-values for the frozen family decision.
A wide interval with no rejection is weak evidence, rather than proof of equivalent strategies.

The verification record contains two real successful executions with:

| Observation | Verified value |
|---|---|
| Pilot outcome and approval | Insufficient; explicit declared-candidate override |
| Inferential dimensions | Two plans per side, three attacks per plan |
| Family | Six comparisons across three tiers |
| Final physical effects | 108 distinct optimizations and 108 distinct experiments per execution |
| Timing | Three excluded warm-ups and fifteen measured triplets |
| Scientific result | All estimates zero; intervals `[-8,8]`; raw/adjusted p-values one; no rejection |

These values establish protocol execution and durable result reads at small counts.
They do not establish useful precision, power or full calibration.
See the [verification record](history/evaluation2-verification.md#local-evidence-artifacts) for local artifact paths and historical identities.

## Elixir API

Use the public facade and transient return types:

```elixir
alias NetworkDefense.Evaluation2.Study

{:ok, revision} = Study.create_revision(yaml_text)
{:ok, started} = Study.start(revision)
{:ok, waiting} = Study.continue(started.execution_id)
{:ok, report} = Study.pilot_result(waiting.execution_id)
# Choose approval from the accepted report before resuming.
{:ok, _status} = Study.resume(waiting.execution_id, approval)
{:ok, final_status} = Study.continue(waiting.execution_id)
{:ok, result} = Study.result(final_status.execution_id)
```

This illustrates the supported boundary. Production callers must handle each bounded error and state explicitly.
`approval` is `:recommended` or `{:override_insufficient, declared_candidate_id}`.
The revision value is `Study.Revision`, rather than a private database row or Gust run ID.
No direct phase dispatch, snapshot insertion or private statistics payload is required.

## Continuation, failure and cancellation

| Situation | Operator action and limit |
|---|---|
| Caller returns at finite API timeout | Keep the application alive. Call `continue(id)` again when needed; timeout does not cancel work |
| Caller disappears after a completed tier | Continue in a compatible runtime. Canonical Gust receipts reconstruct completed timing |
| Whole VM or clock dies mid-measurement | Inspect the bounded failure. The lost session cannot produce valid missing durations or replacement replicas |
| Work remains between phases | `mix study.continue "$EXECUTION_ID"` drives the next step without granting approval |
| Pilot needs approval | Inspect `study.pilot_result`; use one explicit Final approval |
| Operator cancels | `mix study.cancel "$EXECUTION_ID"` commits cancellation before best-effort Gust stopping |
| Result requested before success | A bounded unavailable error is expected; inspect status instead |
| Measurement label changes | Restore a truthful compatible configuration or stop. Do not relabel changed work merely to bypass the check |
| Failed/cancelled execution | Terminal state stays terminal. A new execution is a separate attempt |

Task retries reuse each item's reserved effects. There is no exactly-once computation guarantee.
Late completion cannot advance a cancelled execution.
Separate-command cancellation is visible through durable state polling.
Underlying optimization/simulation effects can outlive best-effort Gust stopping.

## Safe documentation checks

The example test reads the committed YAML, substitutes fresh sandbox graph/Host identities, and calls the real public constructor.
It checks frozen capacity, group/family structure, inherited policies and derived bounds.
It dispatches no study, optimization or simulation work.
After verifying both Repo targets, run from `src/`:

```sh
MIX_ENV=test mix test test/network_defense/evaluation2/documentation_example_test.exs
```

Use authorized local test connection variables before that command.
The default test alias creates/migrates the configured test database, so target verification must precede it.
SQL Sandbox rolls back the example's graph and revision inserts.
This constructor check complements the recorded service-backed evidence; it does not claim a new full study or calibration pass.

Public and major internal module docs use `@moduledoc` and `@doc`.
The project currently has no ExDoc dependency, `mix docs` task or Mermaid renderer configuration.
Source/compiled documentation and diagram-to-code checks are therefore separate from rendered HTML verification.
The [verification record](history/evaluation2-verification.md#documentation-checks) records documentation checks and rendering limits.
