# Goal 02 — Native numerics

## Outcome and clock

- Start UTC: **2026-10-31T14:16:38Z**.
- Deadline UTC: **2026-10-31T17:16:38Z** (10,800 seconds).
- Reserved verification/report window: **17:01:38Z**.
- Scoped completion audit UTC: **2026-10-31T14:51:00Z**; elapsed about 34 minutes.
- Status: **verified complete for Goal 02**. Goal 03 shares this run's original deadline; resume does not reset it.
- Goal 01 source and current regression passed before integration. Final workflow, complete statistical calibration and retirement remain later milestones.

## Assignments

| Helper | Scope and outcome |
|---|---|
| `numerics-inputs`, worker, `deepseek/deepseek-flash` | Pinned dependencies, Matrix helpers, validated inputs, cyclic matching cover and tests. Ownership returned. |
| `numerics-anchors`, worker, `deepseek/deepseek-flash` | Independent sequential reference, numerical cases and runner scaffold. Follow-up reduced the runner to bounded smoke scope. Owner integrated and corrected it. |
| `numerics-scout`, read-only, `deepseek/deepseek-flash` | Existing contracts, IID-input applicability, bounds and PLT diagnosis. |
| `numerics-review`, reviewer, `deepseek/deepseek-flash` | Approved mathematical core; identified two robustness defects and documentation/evidence gaps. Owner addressed them below. |

Both initial workers received the same deadline, disjoint ownership, and instructions to address Credo and formatter findings. No helper delegated recursively. All helpers finished. The owner implemented betting, inversion, comparison, Holm and planning arithmetic, then integrated and checked the result.

## Prompt-to-artifact completion audit

The concrete deliverable is one deterministic native matching-based bounded-mean kernel, with valid input preparation, precision planning helpers, Decimal Holm and scoped numerical evidence.

Paths below are relative to `src/` unless stated otherwise.

| Explicit requirement | Artifact and inspected evidence |
|---|---|
| Prerequisite and governing contracts | Goal 01 checkpoint, current definition/collection source, goal README, full brief, sketches, test plan, statistical validation/checks informed implementation. Current focused and full regression passed. |
| Original three-hour clock and worker constraints | Clock and assignments above. Goal 03 did not start before this audit. |
| Nx float64 inputs and rectangular cover | `study/compute/input.ex`, `matching.ex`, `study/matrix.ex`; input and cover tests check both orientations, every cell once, distinct row/column coordinates and logical order. |
| Frozen finite model bounds | Input validation rejects invalid, non-finite, misaligned and out-of-range data. Construction/collection retain model-derived bounds. Tests include structural zero, extreme finite ranges and raw integer bounds before float conversion. |
| Exact selected past-only recipe | `compute/betting.ex` prepares independent matching histories with the declared initial mean/variance, past prediction errors, fixed horizon and half-range caps. Sequential reference, hand products and independent review check the updates. |
| Arithmetic capital averaging via log-sum-exp | `Betting.log_capitals/2`; hand products and separate-history tests distinguish averaging capitals from averaging logs or multiplying matchings. Constant-column cases check non-inflation. |
| Sign-conservative two-sided p-values | `Betting.p_value/2` retains factor two, chooses the all-cell estimate's direction, returns one for zero, bounds in log space and floors positive underflow at the smallest normal float64. A long single-capital probe tests the floor cheaply. |
| Monotone conservative inversion/fallback | `compute/intervals.ex`, `Compute.compare/2`; outer brackets, 1e-10 normalized tolerance, at most 64 bisections, estimate enlargement and closed bounds. Alternating 20x20 data exercises actual empty inversion: full range, p=1, non-informative warning. |
| Decimal Holm | `compute/holm.ex`; cumulative sorted adjustment, canonical ties/order, capping, inclusive decisions, decimal-boundary case and emitted-float step correction. Subnormal raw probabilities also work. |
| Pilot subset/guard helpers at shared confidence | `compute/pilot_precision.ex`; common outcome-independent row/column permutations across candidates, without replacement, aligned sides, restored logical order, linear-interpolation quantile and unchanged inference confidence. Full-pool repetition adds no evidence. Malformed settings return errors. |
| Planning stream allocation | Existing SHA-256/JSON roots derive outer row/column keys; pinned Nx Threefry shuffles implement permutations. `Randomness.validate/1` now includes outer roots. The caller must reuse the comparison planning seed across candidates. |
| Deterministic Final comparison; no bootstrap/null RNG | `Compute.compare/2` uses no sampling. Repeatability tests compare complete outputs. No compatibility engine, fallback to Python or registry was added. |
| Independent anchors, rare-event safety and scaling | `test/support/evaluation2_numeric_anchors.ex`, `compute_test.exs`, `compute_policy_test.exs`. Five missed rare rows give p=1 and a wide interval. At 160 pairs the independent Decimal/Python calculation gives p=0.00087176606822960337; the 36-member Holm anchor rejects at 0.05. Non-binary scaling preserves p-values and scales estimates/endpoints. |
| Runnable statistical entrypoint and smoke | `scripts/evaluation2_statistical_check.exs --smoke`; final output in `/tmp/evaluation2-goal02-smoke-final.log`. Three declared scenarios, two count pairs, 20 datasets per cell, seed 20261030; independent scenario/replicate/role streams, Wilson intervals and predeclared conservative Hoeffding diagnostic flags. This is reduced smoke evidence, not Goal 06 calibration. |
| Primary-source attribution and assumptions | `Compute` module documentation and applicability section below distinguish published principles from this exact crossed adaptation. |
| Dependency pinning and performance | Nx **1.0.0**, explicit Decimal **3.2.0**, locked Complex **1.0.0**. CPU BinaryBackend probes below establish scoped cost; EXLA was not needed for these workloads. |
| Compile, focused checks, lint, format, regression | Exact commands and outcomes below. `mix precommit` passes after the PLT fix. |
| Preserve unrelated work/data and forbidden scope | No commits, reset, Terraform apply, legacy/Python removal, credentials change, shared-domain replacement or remote operation. Existing dirty files remain. Helper target error is disclosed below. |

## Executed checks

From `/home/michalo/master_thesis/src`, owner database-dependent commands used:

```sh
set -a
. ./.env
set +a
export REPO_PASSWORD_FILE=/home/michalo/master_thesis/infra/environments/local/secrets/postgres-password
```

Before writes, `MIX_ENV=test mix run --no-start --no-compile` checked both Repo configurations: localhost:5433, `network_defense_test`, postgres, SQL Sandbox, password present. `/tmp/evaluation2-goal02-targets.log` omits credentials.

| Command | Final evidence |
|---|---|
| `timeout 90 mix compile` | Exit 0, `/tmp/evaluation2-goal02-compile.log` |
| `MIX_ENV=test mix test` over `compute_policy_test.exs`, `compute_input_test.exs`, `compute_test.exs`, `matching_test.exs`, `randomness_test.exs` | 67 passed before the last three review/boundary cases; `/tmp/evaluation2-goal02-focused-final.log`. All later cases pass in the final full run. |
| `MIX_ENV=test mix test test/network_defense/evaluation2/compute_policy_test.exs` | Final 13 passed, including both review defect regressions; `/tmp/evaluation2-goal02-review-green.log` |
| `MIX_ENV=test mix run --no-start scripts/evaluation2_statistical_check.exs --smoke` | Exit 0; anchors agree; all six scenario cells report 0/20 rejections, Wilson [0,0.1611]; no diagnostic excess flags. Application and both Repos remain stopped. `/tmp/evaluation2-goal02-smoke-final.log` |
| `MIX_ENV=test timeout 240 mix precommit` | **Exit 0**: compile, generated contracts, Elixir/frontend format and type checks, assets, strict Credo, Dialyzer, Sobelow, dependency check and **828 passed, 2 excluded**. `/tmp/evaluation2-goal02-precommit-final.log` |
| `mix format --check-formatted scripts/evaluation2_statistical_check.exs`; strict Credo; `git diff --check` | Exit 0. No added warning filters. |

Smoke metadata includes source/dependency identities and backend. Known-effect smoke cells also have zero rejection: this visibly weak small-sample result is not a power claim.

Performance, measured with `MIX_ENV=test mix run --no-start` and `:timer.tc` around production calls:

- One 100x200 comparison: **1.781245 s**, p=0.01577225404207414; `/tmp/evaluation2-goal02-performance.log`.
- Pool 30x60, candidate 20x40, 32 outer subsets, seed 20261030, confidence 0.95, guard 0.9: **2.168426 s**, guarded half-width 0.28965319180861115; `/tmp/evaluation2-goal02-pilot-performance.log`.
- Independent reviewer measured 369x1476 at about **49.2 s**. Large full empirical workloads can require optimization before Goal 06. This milestone does not claim practical speed at arbitrary dimensions or a full calibration pass.

## Applicability, review and fixes

The source trace confirms row-owned optimizer/scoring seeds, distinct evidence roots and shared attack columns. CVSS ranking is deterministic; its repeated rows are expected. Paired strategy rows stay together. Matching observations have distinct row/column inputs. Family comparisons may remain dependent. Supported actions remove edges and retain capability weights, so frozen positive-weight sums remain valid bounds.

Independent IID role inputs remain a simulation modeling assumption. Different PRNG labels alone do not prove independence. Final collection behavior remains a later milestone.

Primary sources were checked through the authors' arXiv records: Waudby-Smith/Ramdas, arXiv:2010.09686v7 (predictable bounded-mean betting), and Vovk/Wang, arXiv:1912.06116v4 (arithmetic e-value averaging; DOI 10.1214/20-AOS2020). Publisher pages blocked automated retrieval. The cyclic crossed cover, fixed variance recipe and half-range caps are our declared adaptation. The cited papers do not validate the whole pipeline.

Owner fixes and review disposition:

1. Tight arithmetic checks exposed implicit scalar float32 conversion. Computed tuning constants, candidate means, caps, offsets and model ranges now enter Nx explicitly as float64.
2. Mean calculation normalizes before summing to avoid overflow of finite outcome sums. Raw integer bounds are checked before conversion can round an out-of-range value inward.
3. Reviewer approved the mathematical core. Its subnormal Decimal conversion and malformed Pilot settings findings now have failing-then-passing regressions. Float conversion supports subnormals while retaining Decimal decisions.
4. Precision targets explicitly use outcome units, like returned interval spans. Statistical examples with model range one use those same normalized outcome units. No silent range-dependent conversion was added.
5. Initial `mix precommit` failed because Dialyxir included project/consolidated modules in its dependency PLT; the failed update left Nx absent and produced 45 unknown-function/type warnings. `plt_ignore_apps: [:network_defense]` keeps project modules in direct analysis and out of the dependency PLT. A real PLT update and final precommit pass confirm the fix; no warning was suppressed.
6. Initial full regression failed only the strict-Credo self-test during unfinished scaffolding. Final precommit regression passes.
7. The anchor helper's claimed unreachable empty inversion was incorrect; the owner case exercises it. The helper remains an oracle only for its supported regular inversion cases.

### Helper target incident

The anchor worker, and independently the reviewer, invoked the Mix test alias without loading the local environment first. They reached default localhost:5432 `network_defense_test` and received `duplicate_column execution_config`. This violated the instructed target-check order. They stopped DB commands and used offline arithmetic checks afterward. The owner did not reset or repair that other instance. Owner checks use the verified 5433 target and pass. Later helper instructions explicitly prohibit DB commands. No development or remote target was reported by those commands, and no reset was issued.

## Changed artifacts and remaining scope

Owner source: `study/compute.ex`, `study/compute/{betting,intervals,holm,pilot_precision}.ex`, `study/randomness.ex`, precision unit comment, result method/warning declarations, and the Dialyxir configuration. Worker source: input/matching/Matrix, pinned dependencies and numerical fixtures/tests/runner, integrated by the owner. Documentation: this checkpoint and goal README.

Unused old numerical declaration scaffolds remain outside the constructed definition. Their retirement belongs to the later deletion gate. No runtime compatibility path was added.

**Scoped audit result at 14:51Z:** every Goal 02 deliverable has direct source or execution evidence. The numerical gate passed before Goal 03 started.

**Combined audit at 16:00:28Z:** Goal 03 also passes. The final serialized `mix precommit` verifies the retained numerical and Pilot scope together: **867 passed, 2 excluded**, all source/frontend/static gates passed. Credo and formatter now include the statistical runner's `scripts/` directory. See `03-pilot-workflow.md` and `/tmp/evaluation2-goals02-03-final-gate.log`. The combined objective is complete under the original shared deadline.
