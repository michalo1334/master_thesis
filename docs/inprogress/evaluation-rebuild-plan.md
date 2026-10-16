# Evaluation rebuild — current stage

## Status

**Stage 1 is accepted.** The legacy evaluation implementation is removed; the independent graph, simulation, and optimization application remains. The scientific methodology is preserved in reviewed documentation.

The lead reviewed the [final handoff](evaluation-stage-1-handoff.md), actual worktree, diff hygiene, removed subsystem paths, targeted runtime-reference scan, retained optimization-helper rename, and test exclusions. The handoff records successful fresh-test-database migration and full test/build/static checks. The remaining RabbitMQ exclusion is pre-existing; the obsolete rehearsal exclusion is removed.

No commit was created. No later stage is selected or started. Stop here until the user directs further work.

## Focus

Work on Stage 1 only. Do not predefine later implementation stages or keep a speculative backlog.

The lead owns intent, scope, methodology documentation, and acceptance. The interactive `openai/gpt-5.6-sol` agent owns cleanup and verification. The user can direct it in its pane.

## Shared workspace

- Worktree: `/home/michalo/master_thesis-evaluation-rebuild`
- Branch: `evaluation/rebuild`
- Historical reference: `d94ba40352e469dc1c2da403ad3fa28397e5e350`

Use this same worktree for all work. Do not edit the original `/home/michalo/master_thesis` worktree or create another worktree.

## Latest scope — full evaluation clean slate

The user deleted the evaluation directory and expanded cleanup to the entire evaluation subsystem. This supersedes the earlier analysis-only boundary and the instructions to retain evaluation collection/reporting/specification behavior.

Do not restore the deleted directory. Remove remaining evaluation-owned code and dependencies so the retained non-evaluation application compiles and works. Do not create replacement evaluation behavior, compatibility shims, placeholder modules, or new analysis contracts.

### Remove

- Remaining evaluation modules/facades and all callers of deleted evaluation code.
- Evaluation and study execution, persistence, specification-management, reporting, and dashboard behavior that belongs to this subsystem.
- Evaluation/study API and event contracts, generated contract entries, UI state, navigation, and routes.
- Evaluation tests/fixtures, Mix tasks, scripts, infrastructure/configuration, and obsolete dependencies/setup instructions.
- Evaluation-specific schema/migration history and associations/columns that no current independent feature needs.
- Archive/export/import behavior and its tests. No ZIP exception.

Inspect mixed modules and test suites. Remove evaluation-owned portions; retain only genuinely current non-evaluation behavior. Do not keep unused evaluation helpers because a rewrite might reuse them.

### Destructive migration policy

There is no existing-schema, existing-data, or upgrade-compatibility preservation requirement. Rewrite migrations and recreate project databases as needed. Verify the configured target before destructive commands; unrelated databases and infrastructure are outside scope.

The current required graph/simulation/optimization application schema must still work from a fresh database. Do not preserve an obsolete migration chain merely to keep old records.

### Preserve methodology, not implementation

The scientific methodology remains the reference for the rewrite. Recover it from the historical Git baseline and retain it as current documentation. Do not preserve old executable code, obsolete tests, archives, setup commands, or APIs to serve that purpose.

The methodology is preserved in [the methodology reference](../concepts/evaluation-methodology.md), recovered from the historical baseline. It records the scientific protocol, estimand, resampling/correction rules, and known source inconsistencies. The lead maintains that file; the cleanup agent must not delete or concurrently author it. Its historical source references are Git references, not a reason to retain old executable code.

Documentation status: recovery and factual review are complete, with no remaining factual review blockers. This confirms fidelity to the baseline sources, not verification of new evaluation code or a new statistical validation study.

Remove obsolete active implementation/setup instructions. Keep the current-stage brief and relevant accepted design/decision records, clearly distinguished from the deleted implementation. Do not invent replacement design or a future delivery plan.

### Pristine-code rule

Delete obsolete behavior and its tests. No skipped legacy suites, disabled implementations, compatibility shims, legacy folders, inactive backups, commented-out code, or speculative scaffolding. Git history is recovery.

Preserve unrelated user working changes and genuinely independent current functionality. That is a scope boundary, not an obligation to retain evaluation data or code.

## Verification and handoff

Verify the retained application without evaluation code: compilation, current contracts, relevant frontend/backend tests, formatting/static checks, and fresh-schema migration checks as appropriate. Do not make old tests pass by recreating deleted evaluation functionality.

Update `docs/inprogress/evaluation-stage-1-handoff.md` with actual removals, current behavior, fresh-migration evidence, checks/results, and unresolved blockers. State explicitly that evaluation implementation is removed and methodology is preserved in documentation. Describe the resulting state; do not prescribe future stages.

Do not commit, run live evaluation collections, stop unrelated user services, apply/destroy infrastructure, or edit the original worktree. A failed check or partial cleanup is not a completed stage.
