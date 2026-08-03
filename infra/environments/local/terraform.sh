#!/usr/bin/env bash
set -euo pipefail

directory="$(cd "$(dirname "$0")" && pwd)"
repository="$(cd "$directory/../../.." && pwd)"

if [[ ! -f "$directory/.env" ]]; then
  echo "Missing $directory/.env. Copy .env.example and set its values." >&2
  exit 1
fi

if ! command -v docker >/dev/null; then
  echo "Docker is required to run Terraform." >&2
  exit 1
fi

exec docker run --rm \
  --env-file "$directory/.env" \
  -v "$repository:$repository" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w "$directory" \
  hashicorp/terraform:1.15.8 "$@"
