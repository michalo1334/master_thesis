#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose -f docker/docker-compose.yml"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  infra       Start Postgres + pgAdmin + observability stack (app runs locally)
  dev         Full dev stack with hot-reload
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

case "${1:-}" in
  infra)
    $COMPOSE up -d postgres otel-collector pgadmin
    echo ""
    echo "Run the app locally:"
    echo "  cd src"
    echo "  OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 mix phx.server"
    echo ""
    echo "pgAdmin: http://localhost:5050 (admin@admin.com / admin)"
    ;;
  dev)
    if ! docker image inspect network_defense:dev &>/dev/null; then
      echo "Image network_defense:dev not found, building..."
      $COMPOSE -f docker/docker-compose.dev.yml build
    fi
    $COMPOSE -f docker/docker-compose.dev.yml up -d
    ;;
  logs)
    if [ -n "${2:-}" ]; then
      $COMPOSE -f docker/docker-compose.dev.yml logs -f "$2"
    else
      $COMPOSE -f docker/docker-compose.dev.yml logs -f
    fi
    ;;
  down)
    $COMPOSE -f docker/docker-compose.dev.yml down
    ;;
  down-all)
    $COMPOSE -f docker/docker-compose.dev.yml down -v
    ;;
  *)
    usage
    ;;
esac
