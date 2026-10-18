# Evaluation rebuild Stage 2 handoff

## Status

Stage 2 is implemented and verified in the shared worktree.

- Worktree: `/home/michalo/master_thesis-evaluation-rebuild`
- Branch: `evaluation/rebuild`
- Current commit: `18864de022f3cf807d682b898eb114ad4e68763e`
- Gust version: `0.1.40`
- New command-fix changes committed: no
- Live scientific evidence collected: no

The prototype uses synthetic evidence. It does not make a complete study claim.

## Implemented boundary

The deployed path is:

```text
Mix command → Gust run → deployed application worker
    → site-local Python HTTP computation
    → validated Gust task result → Mix read-back
```

Gust owns scheduling, retries, run state, task errors, and result persistence. Python performs one synchronous corrected crossed-bootstrap calculation. Python has no database, job registry, result lookup service, or orchestration role.

The command is:

```text
mix evaluation.compare --fixture crossed-small
```

It starts Gust in console role with one database connection. It does not start the Network Defense supervision tree, web listeners, application repository, Oban, or RabbitMQ workers.

Named synthetic fixtures are packaged under application `priv`. The shared repository paths are symbolic links to the same canonical files. This keeps one copy for Elixir, Python, and deployed command checks.

## Scientific output

The comparison returns:

- alternative-minus-CVSS mean mission-impact difference;
- corrected crossed-bootstrap percentile interval;
- centered crossed-bootstrap two-sided raw p-value;
- informative or non-informative assessment; and
- a warning for an informative zero-width interval.

It preserves independent plan-row resampling and shared attack-column resampling. It uses separate deterministic interval and null streams. The result contains a raw p-value only. It is not a complete-family or Final-study result.

## Deployment apply

The user approved the local apply after plan review. Terraform applied exactly these replacements:

- application development image;
- application setup container;
- four application containers;
- evaluation-compute image; and
- two evaluation-compute containers.

Terraform reported:

```text
9 added, 0 changed, 9 destroyed
```

No database, volume, network, messaging, proxy, or observability resource changed. A plan after apply reported no changes.

All 24 managed containers are healthy, or they are successful one-shot containers with exit status zero.

## Deployed manual proof

The documented command ran twice from a deployed application container. Gust stored runs `4` and `5`. Each `compare` task succeeded on its first attempt, had no stored error, and stored method `corrected_crossed_bootstrap_v1`.

Both runs returned identical stored statistics:

```text
Difference: -1.444
95% CI: [-1.5312, -1.3544]
Raw p: 0.0001
Assessment: informative
```

The exact stored JSON statistics were equal. The site-east Python service logged two successful HTTP `200` requests to the corrected crossed-bootstrap endpoint.

The invalid command was:

```text
mix evaluation.compare --fixture attack-column-count-mismatch
```

It returned `validation_failed` with `attack_column_count_mismatch`. It reported `Run: not created` and `Stored result: none`. The Gust run count did not change.

## Automated verification

| Check | Result |
|---|---|
| Focused Elixir evaluation and Mix-task tests | 47 passed. |
| Complete Elixir precommit suite | 464 passed; 2 existing RabbitMQ exclusions. |
| Python compute tests | 47 passed; 1 known Starlette/AnyIO deprecation warning. |
| Python Ruff format and lint | Passed. |
| Elixir warnings-as-errors compilation | Passed. |
| Elixir format, Credo, Dialyzer, and Sobelow | Passed. |
| Generated contracts and frontend static/build checks in precommit | Passed. |
| Shared fixture byte comparison | All 60 moved files are unchanged. |
| Git diff check | Passed. |

Expected failure-path tests emitted error logs. Existing Vite notices and one existing unused-alias warning remained non-failing.

## Source locations

| Concern | Location |
|---|---|
| Developer command | `src/lib/mix/tasks/evaluation.compare.ex` |
| Gust-only console bootstrap | `src/lib/network_defense/evaluation/comparison/console.ex` |
| Workflow submission and result read-back | `src/lib/network_defense/evaluation/comparison/workflow.ex` |
| Reusable comparison action | `src/lib/network_defense/evaluation/comparison/actions/compare.ex` |
| Gust prototype DAG | `src/priv/gust/dags/evaluation_comparison.exs` |
| Python endpoint and calculation | `services/evaluation_compute/src/evaluation_compute/` |
| Canonical schemas and fixtures | `src/priv/evaluation/contracts/v1/` |
| Preserved scientific reference | `docs/concepts/evaluation-methodology.md` |

## Excluded scope

Stage 2 does not include evidence collection, study specifications, precision Pilot, Final collection, manual phase gates, complete-family Holm correction, secondary reports, or dashboard work.

## Blockers

None for the bounded prototype.

No later implementation increment is selected or started.
