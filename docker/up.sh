#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  infra       Start Postgres + pgAdmin + observability stack (app runs locally)
  dev         Full dev stack with hot-reload
  prod        Start the private demo deployment using PROD_ENV_FILE
  logs        Tail logs
  down        Tear down dev stack
  down-all    Tear down everything including volumes

Examples:
  cd "$ROOT"
  $(basename "$0") infra
  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 mix phx.server
EOF
  exit 1
}

cd "$ROOT"

dev_compose() {
  if [[ ! -f src/.env ]]; then
    echo "Missing src/.env. Copy src/.env.example and set its values first." >&2
    exit 1
  fi

  docker compose --env-file src/.env \
    -f docker/compose.app.yml \
    -f docker/compose.postgres.yml \
    -f docker/compose.observability.grafana.yml \
    -f docker/compose.tools.yml \
    -f docker/compose.dev.yml \
    --profile tools "$@"
}

prod_compose() {
  : "${PROD_ENV_FILE:?set PROD_ENV_FILE to the deployment environment file}"

  docker compose --env-file "$PROD_ENV_FILE" \
    -f docker/compose.app.yml \
    -f docker/compose.postgres.yml \
    -f docker/compose.observability.grafana.yml \
    -f docker/compose.prod.yml "$@"
}

case "${1:-}" in
  infra)
    dev_compose up -d postgres otel-collector tempo prometheus loki alloy grafana pgadmin
    echo ""
    echo "Run the app locally:"
    echo "  cd src"
    echo "  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 mix phx.server"
    echo ""
    echo "pgAdmin: http://localhost:5050"
    ;;
  dev)
    if ! docker image inspect network_defense:dev &>/dev/null; then
      echo "Image network_defense:dev not found, building..."
      dev_compose build
    fi
    dev_compose up -d
    ;;
  prod)
    prod_compose up -d
    ;;
  logs)
    svc=""
    tail=""
    for arg in "${@:2}"; do
      if [[ "$arg" == --tail=* ]]; then
        tail="$arg"
      else
        svc="$arg"
      fi
    done
    log_args=(logs -f)
    [[ -n "$tail" ]] && log_args+=("$tail")
    [[ -n "$svc" ]] && log_args+=("$svc")
    dev_compose "${log_args[@]}"
    ;;
  down)
    dev_compose down
    ;;
  down-all)
    dev_compose down -v
    ;;
  *)
    usage
    ;;
esac
