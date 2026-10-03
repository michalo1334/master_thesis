# Credo guardrail verification

## Commands and results

All commands ran in this worktree. I unset `MIX_DEPS_PATH`. `mix deps.get` fetched the locked dependencies into `src/deps`; no dependency path points at another checkout.

| Command | Status | Result |
| --- | ---: | --- |
| `env -u MIX_DEPS_PATH MIX_ENV=test mix deps.get` | 0 | Locked dependencies fetched. |
| `env -u MIX_DEPS_PATH mix credo.test` (no `MIX_ENV`) | 0 | 6 passed; confirms the preferred test environment. |
| `env -u MIX_DEPS_PATH MIX_ENV=test mix format --check-formatted` | 0 | Formatted. |
| `env -u MIX_DEPS_PATH MIX_ENV=test mix credo --strict` | 0 | 6 advisory findings; no strong finding. |
| `env -u MIX_DEPS_PATH MIX_ENV=test mix credo -C project_strong` | 0 | No findings across 350 source files. |
| `env -u MIX_DEPS_PATH MIX_ENV=test mix credo -C project_heuristics` | 0 | 3 advisory findings across 350 source files. |
| `REPO_PORT=55439 REPO_USERNAME=postgres env -u MIX_DEPS_PATH MIX_ENV=test mix test test/network_defense/credo/project_checks_test.exs test/network_defense/credo/error_codes_match_type_test.exs` | 0 | 7 passed, including the existing error-code check. |
| `npm ci` | 0 | Installed the locked frontend dependencies in this worktree. |
| `env -u MIX_DEPS_PATH MIX_ENV=test mix assets.build` | 0 | Built the frontend manifests in this worktree. Vite reported a large-chunk advisory. |
| `REPO_PORT=55439 REPO_USERNAME=postgres env -u MIX_DEPS_PATH MIX_ENV=test mix test` | 0 | 867 passed, 3 excluded. |

The first full test run, before the frontend build, exited 2: 749/867 passed and 118 tests lacked `_build/test/lib/network_defense/priv/static/.vite/manifest.json`. The locked frontend install and asset build fixed that setup condition. The second full run passed. It emitted expected test-generated error logs and existing migration compile warnings; none failed the run.

## Real CLI fixture evidence

`bash planning/credo-guardrails/verification-fixtures/run.sh` exited 0. It copies synthetic fixtures into real `lib/` paths, runs Credo against those paths, checks finding text and line numbers, checks exit statuses, and removes the temporary source files. The reproducible fixture source and script are in `verification-fixtures/`.

| Profile | Check | Expected CLI finding | Exit |
| --- | --- | --- | ---: |
| `project_strong` | `FlattenedProjectionContract` | Namespace policy message at `lib/guardrail_fixtures/flattened.ex:2` | 16 (nonzero) |
| `project_strong` | `RetiredProjectionTypeHelper` | Retired `node_type/1` policy at `lib/guardrail_fixtures/retired.ex:2` | 16 (nonzero) |
| `project_strong` | `LiveViewRepoDependency` | Direct Repo boundary message at `lib/network_defense_web/live/guardrail_fixture.ex:2` | 16 (nonzero) |
| `project_heuristics` | `InlineContractTypeMapping` | Mapping review message at `lib/guardrail_fixtures/contract_mapping.ex:2` | 0 |
| `project_heuristics` | `SuccessShapedExitCatch` | Success-shaped exit catch review at `lib/guardrail_fixtures/exit_catch.ex:6` | 0 |
| `default` | `FlattenedProjectionContract` | Same strong fixture and line | 16 (nonzero) |
| `default` | `SuccessShapedExitCatch` | Same advisory fixture and line | 0 |

Control fixtures also passed with no findings: a `:throw` catch; an unrelated private helper name; a LiveView with unqualified `Repo` and dynamic dispatch/alias syntax; and a domain file that uses Repo outside LiveView scope.

## Repository findings and limits

The three heuristic-profile findings are intentional review requests for cleanup catches returning `:ok`:

- `lib/network_defense/compute/rabbit_mq_executor.ex:250` (`delete_queue/1`)
- `lib/network_defense/compute/rabbit_mq_executor.ex:256` (`close_channel/1`)
- `lib/network_defense/compute/rabbit_mq/worker.ex:206` (`close_channel/1`)

The default strict run reports these three and three matching cleanup catches in `test/network_defense/compute/rabbit_mq_broker_integration_test.exs` at lines 119, 125, and 131. These remain advisory. Strong-profile source analysis found no findings. No new guardrail finding was suppressed.

The checks analyze the declared source shapes only. CLI controls cover direct file discovery and selected nonmatches. They do not test dynamic dispatch or transitive dependencies beyond the rules' stated scope.

## Isolation

The full tests used only a new PostgreSQL 16 container, bound to `127.0.0.1:55439`, with trust auth scoped to that disposable container. The container was removed after the tests. No existing container or development database was changed. Fixture source files were removed after CLI checks. Dependencies, frontend packages, and build products remain only in this worktree. No app-source or service configuration changes were made for verification.

## Final recheck

All final commands ran in `/tmp/master-thesis-credo-guardrails`; `MIX_DEPS_PATH` was unset where Mix ran.

| Command/check | Status | Result |
| --- | ---: | --- |
| `mix format test/network_defense/credo/project_checks_test.exs` | 0 | Formatted the changed project-check test. |
| `mix credo.test` | 0 | 6 passed. |
| Collision guard: create only `src/lib/guardrail_fixtures/flattened.ex` with a unique sentinel, then run `bash planning/credo-guardrails/verification-fixtures/run.sh` | 1 (expected) | Script refused to overwrite the path; sentinel contents were unchanged, then only the sentinel and its empty directory were removed. |
| `bash planning/credo-guardrails/verification-fixtures/run.sh` | 0 | 11 expected finding/control cases passed; all temporary `src/lib` fixtures were cleaned up. Run with `bash` because the checked-in script is not executable. |
| `mix credo --strict` | 0 | 6 existing advisory findings; no strong finding. |
| Local Markdown links/fragments in `docs/credo-guardrails.md`, `planning/credo-guardrails/*.md`, and `planning/credo-guardrails/research/*.md` | 0 | 9 files checked; 6 local links resolved, no missing paths/fragments. |
| `git diff --check` | 0 | No whitespace errors. |
| Scope/dependency/fixture audit | 0 | All 30 changed/untracked paths are allowed deliverables; no dependency or lockfile changes, no ignored source deliverables, and no fixture files remain under `src/lib`. |

The only ignored worktree content identified was generated `src/_build/`, `src/deps/`, and `src/node_modules/`; these were not staged. The generated `planning/credo-guardrails/logs/repro_cli.log` is ignored and is not a deliverable.

## Pre-commit lifecycle fix (2026-10-03)

| Command/check | Status | Result |
| --- | ---: | --- |
| `MIX_ENV=test mix format test/network_defense/credo/project_checks_test.exs mix.exs` | 0 | Formatted the lifecycle test and Mix alias. |
| `mix credo.test` | 0 | 6 focused checks passed using the relocated `src/credo/test_runner.exs`. |
| `REPO_PORT=55441 REPO_USERNAME=postgres git commit -m "Add Credo project guardrails"` | 0 | The ordinary `.githooks/pre-commit` ran the complete `mix precommit` chain. Full tests passed: 867 passed, 3 excluded. No setup_all failures or Mix test-file-filter warning. |
| `git diff --cached --check` | 0 | No whitespace errors before commit. |

Credo test setup now reuses a running `Credo.Supervisor`; otherwise, it requires `Application.ensure_all_started(:credo)` to succeed. The test module runs synchronously to prevent application-startup races. The runner now resides in `src/credo/test_runner.exs`, outside the test discovery directory.

The hook used only the disposable PostgreSQL 16 container `master-thesis-static-hook-postgres-20261003`, bound to `127.0.0.1:55441`; it was removed after the successful commit. The verification run and hook output are in the ignored repository-local directory `/home/michalo/master_thesis/local-results/goal-verification/static-hook/`. Commit: `90a55a49d74c78ee932de24f2188bc51151098b3`. The follow-up also records this post-commit evidence.

## Main-agent literal namespace review

A compiled Elixir probe confirmed that an unqualified nested declaration is relative to its containing module, even when its name starts with the project's namespace. The previous traversal incorrectly reported this unrelated scope. A new regression test failed before the correction.

`GuardrailAst.modules/1` now preserves literal parent scope and distinguishes absolute `Elixir.` declarations. All three module-scoped checks use it. Alias and macro expansion remain unsupported. Test fixtures that intended an absolute declaration now say so explicitly.

After correction, `mix credo.test` passed all seven tests. All eleven real CLI positive/negative fixture checks passed. The strong profile scanned 350 production files with no findings; the heuristic profile retained the same three cleanup-catch advisories with exit status zero.

Main-agent logs are under the ignored repository-local `local-results/goal-verification/` directory: `namespace-before.log`, `namespace-after.log`, `namespace-cli.log`, `namespace-strong.log`, and `namespace-heuristics.log`. The final follow-up uses the ordinary commit hook; its output is recorded in `final-commits/static-commit.log`.
