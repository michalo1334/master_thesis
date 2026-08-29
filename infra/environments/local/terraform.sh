#!/usr/bin/env bash
set -euo pipefail

directory="$(cd "$(dirname "$0")" && pwd)"
repository="$(cd "$directory/../../.." && pwd)"
manifest="$repository/infra/deployments/thesis-lab.tfvars"

if ! command -v docker >/dev/null; then
  echo "Docker is required to run Terraform." >&2
  exit 1
fi

terraform_args=("$@")

case "${1:-}" in
  apply|console|destroy|import|plan|refresh)
    terraform_args=("$1" "-var-file=$manifest" "${@:2}")
    ;;
esac

exec docker run --rm --interactive \
  -v "$repository:$repository" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w "$directory" \
  hashicorp/terraform:1.15.8 "${terraform_args[@]}"
