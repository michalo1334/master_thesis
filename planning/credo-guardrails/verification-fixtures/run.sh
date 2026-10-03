#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
cd "$ROOT/src"
export MIX_ENV=test
unset MIX_DEPS_PATH

created=(
  lib/guardrail_fixtures/flattened.ex
  lib/guardrail_fixtures/retired.ex
  lib/guardrail_fixtures/contract_mapping.ex
  lib/guardrail_fixtures/exit_catch.ex
  lib/guardrail_fixtures/controls.ex
  lib/network_defense_web/live/guardrail_fixture.ex
  lib/network_defense_web/live/dynamic_live.ex
  lib/network_defense/domain/guardrail_fixture.ex
)
for path in "${created[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'Refusing to overwrite existing fixture path: %s\n' "$path" >&2
    exit 1
  fi
done

cleanup() {
  rm -f "${created[@]}"
  rmdir lib/guardrail_fixtures 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p lib/guardrail_fixtures lib/network_defense_web/live lib/network_defense/domain
cp "$SCRIPT_DIR/flattened.ex" lib/guardrail_fixtures/flattened.ex
cp "$SCRIPT_DIR/retired.ex" lib/guardrail_fixtures/retired.ex
cp "$SCRIPT_DIR/contract_mapping.ex" lib/guardrail_fixtures/contract_mapping.ex
cp "$SCRIPT_DIR/exit_catch.ex" lib/guardrail_fixtures/exit_catch.ex
cp "$SCRIPT_DIR/controls.ex" lib/guardrail_fixtures/controls.ex
cp "$SCRIPT_DIR/live_view_repo_dependency.ex" lib/network_defense_web/live/guardrail_fixture.ex
cp "$SCRIPT_DIR/dynamic_live.ex" lib/network_defense_web/live/dynamic_live.ex
cp "$SCRIPT_DIR/domain_repo_control.ex" lib/network_defense/domain/guardrail_fixture.ex

check_finding() {
  profile=$1 check=$2 file=$3 expected_line=$4 message=$5
  output=$(mktemp)
  set +e
  mix credo suggest "$file" -C "$profile" --only "$check" --all >"$output" 2>&1
  status=$?
  set -e
  if [[ $profile == project_strong || $check == NetworkDefense.Credo.FlattenedProjectionContract ]]; then
    [[ $status -ne 0 ]] || { cat "$output"; rm -f "$output"; echo "Expected nonzero exit: $check" >&2; exit 1; }
  else
    [[ $status -eq 0 ]] || { cat "$output"; rm -f "$output"; echo "Expected zero exit: $check" >&2; exit 1; }
  fi
  grep -F "$message" "$output" >/dev/null
  grep -F "$file:$expected_line:" "$output" >/dev/null
  printf 'PASS %s %s %s:%s status=%s\n' "$profile" "$check" "$file" "$expected_line" "$status"
  rm -f "$output"
}

check_clean() {
  profile=$1 check=$2 file=$3
  output=$(mktemp)
  set +e
  mix credo suggest "$file" -C "$profile" --only "$check" --all >"$output" 2>&1
  status=$?
  set -e
  if [[ $status -ne 0 ]] || grep -F 'warning' "$output" >/dev/null; then
    cat "$output"; rm -f "$output"; echo "Expected clean result: $check $file" >&2; exit 1
  fi
  printf 'PASS clean %s %s status=%s\n' "$check" "$file" "$status"
  rm -f "$output"
}

check_finding project_strong NetworkDefense.Credo.FlattenedProjectionContract lib/guardrail_fixtures/flattened.ex 2 'Do not flatten a projection contract child'
check_finding project_strong NetworkDefense.Credo.RetiredProjectionTypeHelper lib/guardrail_fixtures/retired.ex 2 'Remove the retired private node_type/1 helper'
check_finding project_strong NetworkDefense.Credo.LiveViewRepoDependency lib/network_defense_web/live/guardrail_fixture.ex 2 'LiveView code must not depend directly on NetworkDefense.Repo'
check_finding project_heuristics NetworkDefense.Credo.InlineContractTypeMapping lib/guardrail_fixtures/contract_mapping.ex 2 'three or more clauses map literal atoms to'
check_finding project_heuristics NetworkDefense.Credo.SuccessShapedExitCatch lib/guardrail_fixtures/exit_catch.ex 6 'Review this catch of :exit'
check_finding default NetworkDefense.Credo.FlattenedProjectionContract lib/guardrail_fixtures/flattened.ex 2 'Do not flatten a projection contract child'
check_finding default NetworkDefense.Credo.SuccessShapedExitCatch lib/guardrail_fixtures/exit_catch.ex 6 'Review this catch of :exit'
check_clean project_strong NetworkDefense.Credo.RetiredProjectionTypeHelper lib/guardrail_fixtures/controls.ex
check_clean project_heuristics NetworkDefense.Credo.SuccessShapedExitCatch lib/guardrail_fixtures/controls.ex
check_clean project_strong NetworkDefense.Credo.LiveViewRepoDependency lib/network_defense_web/live/dynamic_live.ex
check_clean project_strong NetworkDefense.Credo.LiveViewRepoDependency lib/network_defense/domain/guardrail_fixture.ex
