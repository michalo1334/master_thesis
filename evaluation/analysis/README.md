# Statistical Analysis

The analysis reads a completed Phase 1 ZIP export. The ZIP contains
`manifest.resolved.json`, `graph.json`, `plans.jsonl`, `trials.csv`,
`capability_outcomes.csv`, `summary.csv`, and `checksums.txt`.

The resolved manifest declares the strategy runs, comparisons, outcomes,
resampling settings, correction, and pilot precision target. The analysis core
does not use the database or the network. The CLI and HTTP service only
transport the Phase 1 ZIP.

```sh
uv sync --frozen
uv run network-defense-analysis pilot /path/to/export --output /path/to/pilot
uv run network-defense-analysis analyze /path/to/evaluation.zip --output /path/to/analysis
cat evaluation.zip | uv run network-defense-analysis pilot - --output - > pilot.zip
cat evaluation.zip | uv run network-defense-analysis analyze - --output - > analysis.zip
```

Run the commands from this directory. The analysis engine reads local files
only. Treat the reported uncertainty as simulator uncertainty for the exported
scenario.

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
`/v1/analyze` and `/v1/pilot`. The image starts the service by default. Override
the command to run the CLI, for example
`docker run --rm network-defense-analysis network-defense-analysis --help`.

Phoenix uses Req and the explicit task:

```sh
ANALYSIS_SERVICE_URL=http://127.0.0.1:8080 \
  mix evaluate.analyze --run-id RUN_ID --mode analyze --output analysis.zip
```

App containers use the service name through Docker DNS. Host-side Mix commands
use the configurable loopback port. The service has no authentication.

TODO: Add service authentication before non-local or untrusted exposure. Until
then, use the service only on trusted local or private networks.

There is no protobuf or gRPC interface. The service does not add automatic
analysis, Dashboard integration, an Oban analysis job, or artifact persistence.
