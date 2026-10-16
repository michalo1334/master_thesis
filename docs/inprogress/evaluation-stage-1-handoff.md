# Evaluation rebuild Stage 1 handoff

## Status

Stage 1 is complete in the shared worktree.

- Worktree: `/home/michalo/master_thesis-evaluation-rebuild`
- Branch: `evaluation/rebuild`
- Baseline and current `HEAD`: `d94ba40352e469dc1c2da403ad3fa28397e5e350`
- Tracked diff from the baseline: 318 files changed, 190 lines added, and 48,490 lines deleted
- Commit created: no
- Live evaluation run: no
- Infrastructure apply, refresh, or destroy: no

The only destructive command targeted the project test database. The configured
target was verified first as `network_defense_test` on `localhost:5432`, with
`MIX_TEST_PARTITION` unset. The database was dropped, created, and migrated to
prove the retained application from a fresh schema.

The lead-owned methodology document is present at
`docs/concepts/evaluation-methodology.md`. This stage did not edit it. The five
untracked lead planning and review documents also remain untracked and
unchanged:

- `docs/inprogress/evaluation-pipeline.md`
- `docs/inprogress/evaluation-rebuild-plan.md`
- `docs/inprogress/evaluation-stage-integration.md`
- `docs/inprogress/grilling-evaluation.md`
- `docs/inprogress/gust-evaluation-review.md`

## Removed scope

### Complete legacy subsystem

Deleted the complete `evaluation/` tree. This includes:

- the Python analysis service and CLI;
- report, statistics, study, archive, and comparison code;
- Python tests, rehearsal tools, package files, and lockfile;
- local rehearsal inputs;
- optimizer pilot inputs;
- the fixed-order-fulfilment NVD snapshot and provenance;
- the topology-scale study input.

Deleted the Elixir evaluation subsystem. This includes collection, reports,
manifests, plans, observations, workers, preflight, seed schedules, study
specifications, and study execution.

Deleted all evaluation Mix tasks and the fixed-order-fulfilment seed task.
Deleted the matching topology scenario module because its files and task were
part of the removed subsystem.

### Dashboard and transport boundary

Deleted:

- the manifest editor and model;
- study dialogs, documents, models, previews, and result import;
- the analysis report and its navigation;
- all evaluation LiveView events and handlers;
- all evaluation contracts and generated TypeScript imports;
- the completed-run download controller and route;
- evaluation run listing and cancellation support.

The document catalog now contains graphs, simulation reports, and optimization
reports only. The Runs view now contains simulations and optimizations only.

The obsolete optimization helper named `to-analysis.ts` was renamed to
`optimization-presentation.ts`. Its types and callers now use presentation
names. The optimization strategy-analysis UI remains because it belongs to the
independent optimization report.

### Persistence

Deleted every migration that created, changed, renamed, or dropped evaluation,
study, workflow, and legacy analysis data. Updated the mixed cancelled-status
migration so it changes simulation and optimization tables only.

Removed evaluation-owned fields and associations from optimization runs and
simulation experiments. These include run ownership, model variants, and
selection seeds.

The retained migration set contains 31 files. A fresh migration produced no
tables or columns with evaluation, analysis, study, workflow, manifest,
model-variant, or selection-seed names.

### Configuration and infrastructure

Deleted `infra/modules/local/analysis/` and all callers. Removed analysis
service configuration, limits, URLs, dependencies, and ignored output paths.
Removed the Oban evaluation queue and evaluation telemetry metrics.

Removed the stale ExUnit `rehearsal` exclusion. The valid RabbitMQ exclusion
remains.

### Tests and active documentation

Deleted evaluation-only tests and fixtures. Reduced mixed suites to graph,
simulation, optimization, workspace, and application behavior.

Deleted the obsolete evaluation concept page and screenshot. Updated active
README, requirements, scope, vocabulary, graph, architecture, dashboard,
infrastructure, and CI/CD documentation. Active documentation now links to the
lead-owned preserved methodology as the future rewrite reference.

## Retained scope

The following behavior remains:

- graph creation, editing, immutable revisions, folders, and comparison;
- topology projection and canvas behavior;
- attack simulation, progress, cancellation, persistence, and reports;
- defense optimization, progress, cancellation, persistence, and reports;
- optimized graph creation and graph-diff navigation;
- the document catalog and active-runs view for retained document and run kinds;
- local infrastructure and observability for the retained application.

No replacement evaluation module, schema, contract, route, UI, stub, or
compatibility alias was added. No later-stage design or implementation was
started.

## Fresh-schema proof

The database target was checked before the destructive commands:

```text
MIX_TEST_PARTITION=<unset>
database=network_defense_test host=localhost port=5432 user=postgres
```

The following commands passed:

```text
MIX_ENV=test mix ecto.drop
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

An `information_schema.columns` query then searched table and column names for
legacy subsystem terms. It returned an empty list. The complete Elixir test
suite passed against this freshly migrated database.

## Verification

| Command | Result |
|---|---|
| `git diff --check` | Passed. |
| `cd src && mix format --check-formatted` | Passed. |
| `cd src && mix gen.contracts` | Passed; generated files are current. |
| `cd src && mix compile --warnings-as-errors` | Passed. |
| `cd src && MIX_ENV=test mix compile --warnings-as-errors` | Passed. |
| `cd src && npm run format:check` | Passed. |
| `cd src && npm run typecheck` | Passed with 0 errors and 0 warnings. |
| `cd src && npm run lint:color` | Passed. |
| `cd src && npm test -- --run` | Passed: 65 files and 575 tests. |
| `cd src && MIX_ENV=test mix assets.build` | Passed. |
| `cd src && MIX_ENV=test mix test` | Passed: 417 tests, 2 excluded. |
| `cd src && mix credo --strict` | Passed: 1,881 modules/functions and no issues. |
| `infra/environments/local/terraform.sh fmt -check -recursive ../..` | Passed. |
| `infra/environments/local/terraform.sh init -backend=false -lockfile=readonly` | Passed. |
| `infra/environments/local/terraform.sh validate` | Passed. |

The Svelte autofixer reported no issues in the edited components. It repeated
generic effect suggestions for the retained workspace-persistence effect in
`DashboardHost.svelte`. That effect was not changed.

A source scan found no remaining subsystem references under `src/`. A path
scan found no evaluation, analysis, or study implementation path outside the
preserved methodology and lead-owned planning or review documents. The
Prometheus setting `evaluation_interval` remains because that name belongs to
Prometheus, not to the removed subsystem.

Expected failure-path tests emitted error logs. Vite emitted its existing
browser-externalization and large-chunk notices. These messages did not fail a
check.

## Blockers

None.
