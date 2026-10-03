# Goal requirement-to-evidence audit

Objective: deliver two separate branches—an approachable, illustrated README with exercised setup and interview evidence; and researched, tested repository-specific Credo checks.

Both branches start at `5ef2a5073fad040a493ca3add4515e3e1567eb84`. Documentation lives on `docs/project-guide`; static analysis lives on `feat/credo-guardrails`. Paths below belong to the indicated branch. Branch commits and final status must also be inspected; this table alone is not proof of completion.

## Documentation branch

| Explicit requirement | Inspected evidence |
| --- | --- |
| Human README informed by established Elixir projects | Main-agent rewrite in `README.md`; Phoenix, Broadway, and Oban README structures researched in the static branch's `research/elixir-patterns.md` |
| Inspect the last rewrite | `git log -1 -p -- README.md` at the baseline showed a clearer evaluation-index label, not a larger rewritten section; no larger example was invented |
| Concise purpose, core functionality, incentive, no badges | README opens with the defense decision, explains the simulator's limits, and uses three short feature captions; no badges |
| Three or four real screenshots | Exactly `docs/images/topology.png`, `simulation.png`, and `defenses.png`; each 1600×1050; main agent inspected all three |
| Tested getting started | `docs/getting-started-verification.md`: clean tracked-source export, fresh secrets/state/data, Terraform init/validate/plan/apply/output, no-change plan, health checks, and completed browser runs |
| Setup problems addressed | Configuration-derived, non-overwriting `init-secrets.sh`; verified fix for hardcoded frontend public-port settings; original stack untouched |
| Roadmap | README links unfinished cloud tooling and separates planned cloud collection from local demonstration results |
| Repository index links | Local files, image targets, directory links, and fragments checked; GitHub repository returned HTTP 200 |
| Driftrock evidence, current or future | `docs/interview-evidence.md` maps LiveView, Ecto/PostgreSQL, RabbitMQ, OTP/Oban, observability, contracts, and review to source/tests; it labels proposed exercises and unproven experience claims |
| Main agent writes documentation | Main agent authored README, interview guide, verification narrative, and this audit |

The main agent repeated the browser journey after stopping subagent use. It opened the seeded graph, arranged and focused a readable topology, ran a real simulation, and ran CVSS optimization. Completed reports—not fabricated output—supply the screenshots. Started notifications were closed and confirmed hidden before capture.

The documented example produced mean blast radius 2.61 of 16 hosts, mean mission impact 0, and three selected patch actions. These are demonstration results, not final research evidence. A favicon 404 and an ECharts zero-size warning remain documented; neither blocked the captured workflows. Other browser workflows were not exhaustively tested.

The secret helper passed real Terraform-console integration, repeated-run preservation, permissions, syntax, and negative safety cases. The documentation branch's full precommit chain passed with 861 tests and three opt-in exclusions. Raw final browser and helper evidence is under gitignored `local-results/goal-verification/`.

## Static-analysis branch

All research and execution artifacts are under `planning/credo-guardrails/` on that branch.

| Numbered requirement | Inspected evidence |
| --- | --- |
| 1. Established Elixir code/module patterns | `research/elixir-patterns.md`: Phoenix, Ecto, Oban, Broadway, Plug, and Credo sources; follow-up context, changeset, CSRF, and worker-test guidance; version and source limits stated |
| 2. Research ex_slop / supplied ex_dna URL | `research/exslop-exdna-ai.md`: distinguishes the installed ExSlop package from ExDNA; records taxonomy, configuration, clone approach, license evidence, and limits of test inspection |
| 3. Internet research on AI mistakes across languages | Same report: measured security-study evidence and Python/JavaScript package-hallucination research; practitioner observations are not presented as prevalence measurements |
| 4. Propose and implement checks | `design.md`, five check modules plus a small AST helper under `src/credo/checks/`, and `src/.credo.exs` |
| Strong versus heuristic split | Three strong checks and two advisory checks; named profiles; default profile preserves existing checks; real CLI fixtures verify findings, lines, discovery, and exit behavior |
| Repository conventions and user-requested corrections | `research/history.md` links `d40d463` and recorded PR comments to namespace/helper corrections; the new LiveView boundary is explicitly not attributed to an earlier user request |
| Consider supplied detection report | Research accepts its structural-rule versus similarity distinction, notes its illustrative status, and rejects unsupported AI-authorship inference |
| Parallel explorer Luna 6 research saved to files | Research used explicit `openai-codex/gpt-6-luna` overrides and parallel agents; the main agent saved and synthesized reports |
| Main-agent synthesis | `design.md` selects exact local rules rather than copying generic ExSlop checks or adding another clone engine |
| Implementor override | Subsequent implementor calls used the explicit Luna 6 override after the user's clarification |
| Verification and guidance | `verification.md`, reproducible `verification-fixtures/`, `docs/credo-guardrails.md`, and the AGENTS.md guidance |

Final verification includes seven focused tests and the full suite: 868 passed, three opt-in exclusions. The existing error-code check is included in the full suite. Real CLI fixtures cover every new check. Strong findings exit nonzero; heuristic findings remain visible and exit zero. Three real source advisories identify cleanup catches and remain unsuppressed.

Direct review found and corrected missing AST traversal, false literal matching, wrong catch forms, a same-process Credo startup failure, and confusion between relative and absolute nested module names. The namespace regression failed before its correction and passed afterward. The corrected implementation passed the ordinary commit hook, including formatting, frontend checks/builds, Credo, Dialyzer, Sobelow, and tests. No hook was bypassed.

## Boundaries preserved

- User-owned `.pi` edits and the untracked goal/supplied report remain outside the deliverable commits.
- No pushes, merges, production deployment, or real network changes are part of this goal.
- Temporary test databases were separate from development data.
- Research does not prove AI authorship, production scale, personal authorship, TDD, or final cloud-study conclusions.
- After the user stopped subagents, the main agent performed the remaining work directly.
