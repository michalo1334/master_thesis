# Statistical Analysis

## Evaluation archive files

The analysis reads a completed evaluation archive. The archive contains
`manifest.resolved.json`, `graph.json`, `plans.jsonl`, `trials.csv`,
`capability_outcomes.csv`, `pre_attack_flow_statuses.csv`,
`host_compromises.csv`, `summary.csv`, `evaluator_runtime.csv`, and
`checksums.txt`.

The resolved manifest declares the strategy runs, comparisons, outcomes,
resampling settings, and correction. The analysis core
does not use the database or the network. The CLI and HTTP service only
transport the evaluation archive.

```sh
uv sync --frozen
uv run network-defense-analysis analyze /path/to/evaluation.zip --output /path/to/analysis
cat evaluation.zip | uv run network-defense-analysis analyze - --output - > analysis.zip
```

Run the commands from this directory. The analysis engine reads local files
only.

## Single-archive and study analysis

Single-archive commands keep their behavior. The primary interval already
includes plan-selection and attack-outcome variation. It does not include
graph-generation or environment variation.

`study-pilot` and `study-analyze` analyze one study bundle. The bundle is a ZIP
that holds `study.json`, `checksums.txt`, and one tier archive per declared tier
under `tiers/`.

```sh
uv run network-defense-analysis study-pilot study.zip --output pilot.zip
uv run network-defense-analysis study-analyze study.zip --output analysis.zip
```

The service exposes the same modes at `POST /v1/study/pilot` and
`POST /v1/study/analyze`. Both accept and return `application/zip`.

### Crossed estimator

One comparison builds a tested plan-by-attack matrix and a CVSS plan-by-attack
matrix. The bootstrap samples plan rows independently on the two sides. It
samples attack columns once and uses them on both sides. A finite-sample factor
corrects small plan and attack counts. A negative mean contrast favors the
alternative.

The crossed structure matches the design. The old nested structure averaged the
plans before resampling and lost plan-selection variation.

### Study specification and Mix task

One versioned study specification declares the family rules. An example is
`evaluation/studies/topology-scale.json`. It declares the alternative
strategies, the CVSS baseline, the action-count budgets, the primary outcome,
the pilot candidate grid, the precision target, the correction method, and the
disjoint pilot and final seed schedules.

The `mix evaluate.study` task builds the bundle in Elixir and calls the Python
service. Run it from the Elixir project:

```sh
cd src
mix evaluate.study \
  --spec ../evaluation/studies/topology-scale.json \
  --tier small=RUN_ID \
  --tier medium=RUN_ID \
  --tier large=RUN_ID \
  --mode pilot \
  --output study-pilot.zip
```

Use `--mode analyze` for the final family. Statistics stay in Python.

### Pilot, correction, and conservative coverage

The two-dimensional pilot selects one common plan count and attacks-per-plan
count. A candidate passes only when every informative comparison meets the
precision target. A non-informative comparison has a zero contrast and a
zero-width interval. It blocks every candidate and stays in the family.

The final analysis applies one Holm correction across the complete declared
family. High coverage above the accepted range is conservative, not invalid. It
can select a larger sample. Read `informative`, `ci_half_width`, `passes`, and
`p_*` for each comparison. A non-informative row is not a success.

### Current limits

- One frozen graph per tier. The study has no graph replication inside a tier.
- One recorded environment. The results do not cover environment variation.

## Analysis output

The analysis output contains primary, secondary, and capability results. It
also contains descriptive host compromise probabilities, feasibility summaries,
and a runtime summary. The runtime summary gives median plan-selection and
simulation durations, plus the total evaluator duration.

## Comparison

`compare` checks that two completed evaluation archives are semantically equal,
for example two replicas of the same evaluation:

```sh
uv run network-defense-analysis compare /path/to/reference/export /path/to/candidate/export
```

It accepts archive paths or directories. On equality it prints `{"equal":true}`
and exits 0; on a mismatch it prints `{"equal":false, "differences":[...]}`
with the affected dataset names and exits 1. Invalid archives are CLI errors
that exit 2.

Equality covers the resolved manifest and source graph; plan semantics
(variant, strategy, requested budget, selection seed, objective, feasibility,
used budget, actions, status); baseline and defended trial outcomes;
capability outcomes; pre-attack required-flow status; host compromises; and
non-timing summary outcomes. Plan order is normalized by mapping plan IDs to
the stable identity (model_variant, strategy, requested_budget,
selection_seed); baseline rows use a literal identity. Experiment IDs are
ignored and rows are sorted before comparison.

It excludes evaluator, plan-selection, and simulation runtimes, which vary
between replicas. The differences list names only the logical dataset that
diverges, not the raw rows.

## Tests

Run the Python unittest suite from this directory:

```sh
uv run python -m unittest discover -s tests
```

## HTTP service

Build the dedicated image and start the service:

```sh
docker build -t network-defense-analysis evaluation/analysis
docker run --rm -p 127.0.0.1:8080:8080 network-defense-analysis
curl http://127.0.0.1:8080/healthz
curl -H 'content-type: application/zip' --data-binary @evaluation.zip \
  http://127.0.0.1:8080/v1/analyze -o analysis.zip
```

The service accepts raw ZIP requests and returns raw ZIP responses for
`/v1/analyze`. It returns an `application/problem+json`
response with HTTP 413 when the request exceeds the compressed ZIP limit. It
returns the same media type with HTTP 429 when no analysis slot is available.
The image starts the service by default. Override the command to run the CLI,
for example `docker run --rm network-defense-analysis
network-defense-analysis --help`.

Phoenix uses Req and the explicit task:

```sh
ANALYSIS_SERVICE_URL=http://127.0.0.1:8080 \
  mix evaluate.analyze --run-id RUN_ID --output analysis.zip
```

Terraform-managed app containers use the site-local `analysis` alias through
Docker DNS. The Terraform-managed service has no host port. Host-side commands
need a separately published local service. The service has no authentication.

TODO: Add service authentication before non-local or untrusted exposure. Until
then, use the service only on trusted local or private networks.

There is no protobuf or gRPC interface. The service does not add automatic
analysis, Dashboard integration, an Oban analysis job, or artifact persistence.
