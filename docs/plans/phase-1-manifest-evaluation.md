# Phase 1: Manifest Evaluation

## Goal

Run one reproducible evaluation from a saved manifest. The dashboard and the
local CLI use the same evaluation context. A completed analysis report can
download the output contract as a ZIP file.

## Scope

- Replace the current dashboard analysis dialog with a manifest dialog.
- Store editable manifests in PostgreSQL.
- Support an enterprise topology source or an existing graph revision source.
- Run all selected plans and paired attack trials from one immutable source
  graph revision.
- Reuse existing optimization and simulation execution rows.
- Generate the output-contract ZIP on request. Do not retain ZIP files.

## Non-Goals

- Distributed evaluation.
- Statistical analysis and figures.
- Durable object storage.
- A graph ID source. The manifest always identifies an immutable graph
  revision.

## Manifest

The manifest has these required fields:

```json
{
  "schema_version": 2,
  "model_version": "current-model-version",
  "id": "fixed-enterprise-v1",
  "source": {
    "type": "topology",
    "generator": "enterprise",
    "hosts": 50,
    "seed": 42
  },
  "attacker": {
    "entry_host": { "type": "semantic_key", "value": "internet" },
    "max_attempts": 1
  },
  "model": {
    "objective": "mission_then_blast_radius",
    "require_pre_attack_feasibility": true
  },
  "strategy_runs": [{ "strategy": "cvss", "budget": 1, "selection_seeds": [101] }],
  "analysis": { "primary_comparisons": [{ "strategy": "cvss", "baseline": "null", "budget": 1, "outcome": "blast_radius" }], "confidence_level": 0.95, "bootstrap_resamples": 10000, "permutation_resamples": 10000, "multiplicity_correction": "holm", "seed": 7001, "pilot": { "ci_half_width": 0.25 } },
  "evaluation": { "trials": 1000, "seed": 9001 }
}
```

A graph revision source replaces the `source` value and the entry-host
selector:

```json
{
  "source": { "type": "graph_revision", "graph_revision_id": "uuid" },
  "attacker": { "entry_host": { "type": "node_id", "value": "uuid" } }
}
```

The runner resolves a topology source to a new immutable graph revision. It
uses a graph revision source without generating a graph. It stores the
resolved source revision ID on the evaluation run.

## Validation

The manifest contract parses JSON and checks structure. It rejects unknown
fields, invalid versions, invalid source combinations, invalid UUIDs, empty or
duplicate budgets, strategies, or selection seeds, and invalid numeric values.

The runner then preflights the source before it creates execution rows. It
loads or generates the source graph, resolves the entry host, checks mission
feasibility when required, and checks that requested actions exist. This stage
returns field-path errors to the dashboard.

## Persistence

Add these tables:

| Table | Data |
| --- | --- |
| `evaluation_manifests` | Manifest ID, title, and validated JSON content. |
| `evaluation_runs` | Manifest reference, resolved manifest, source graph revision, status, and failure reason. |

Add nullable `evaluation_run_id` to `optimization_runs` and `experiments`.
Add nullable `optimization_run_id` to `experiments`.

An optimization run is a selected plan. Its actions remain in
`optimization_actions`. A post-defense experiment links to the selected
optimization run. A baseline experiment has no optimization run. Terminal
outcomes remain in `simulation_runs` and iteration data remains in
`iteration_steps`.

The database constraints must prevent duplicate plans and duplicate trial
indexes when a run resumes.

## Evaluation Lifecycle

1. Load a saved manifest.
2. Validate it and preflight the source.
3. Create or resume one evaluation run.
4. Resolve the source graph revision once.
5. Build the attack-seed schedule once.
6. Select every plan before post-defense trials start.
7. Run the baseline and each post-defense experiment with the shared schedule.
8. Mark the evaluation run complete only after every experiment completes.

Use `NetworkDefense.Simulation.Seed.child_seed/2` with documented named index
ranges for topology, policy selection, optimizer simulation, and attack
evaluation. Changing a policy-selection seed must not change attack seeds.

## Public Interfaces

Add a local CLI command:

```sh
mix evaluate.manifest --manifest-id MANIFEST_ID
```

Add dashboard events for manifest list, get, save, and start. The start event
contains only a manifest ID. The LiveView starts the shared context in a local
background task.

Add dashboard report events to load an evaluation-run summary. Do not send raw
trial rows to the browser.

## Output Contract

The download route regenerates these files from the evaluation run and its
linked execution rows:

- `manifest.resolved.json`
- `graph.json`
- `plans.jsonl`
- `trials.csv`
- `summary.csv`
- `checksums.txt`

Sort plans and trial rows. Do not include volatile timestamps in the exported
records. Generate a temporary ZIP with Erlang `:zip`, send it, and remove it.
`graph.json` comes from the immutable source graph revision. It is the portable
graph input. The database graph revision remains the runtime source.

## Dashboard

The Analysis ribbon action opens a two-pane manifest dialog. The left pane
lists saved manifests by title and has an Add action. The right pane has a raw
JSON editor, Save action, validation errors, and Start evaluation action.

A completed evaluation opens an analysis-report document. The report shows the
manifest title, source graph, status, and aggregated plan results. The ribbon
Download results action is enabled only while this document is active and its
evaluation run is complete.

## Tests

- Manifest structure and source preflight validation.
- Topology and graph-revision source selection.
- One source graph revision per evaluation run.
- Shared ordered attack seeds for every plan.
- Separation of attack and selection seed streams.
- No duplicate plan, experiment, or trial rows after resume.
- One exported row for each terminal trial.
- Deterministic output-contract file contents for a completed run.
- Dashboard manifest save, start, report, and download affordances.
