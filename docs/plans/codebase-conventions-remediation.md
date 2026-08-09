# Codebase Conventions Remediation

## Goal

Remove the correctness defects and duplicate implementation paths found by the
repository scan without changing the reachability model or published wire
contracts unnecessarily.

## Scope

1. Make generated seeds safe for the database type and keep seed handling in one place.
2. Make simulation and optimization failures reach a terminal persisted state and a client-visible failure event.
3. Convert expected database conflicts into changeset errors where the calling code already expects error tuples.
4. Align optimizer, simulation, and frontend strategy requirements.
5. Consolidate repeated strategy setup, candidate enumeration, report statistics, operational-flow serialization, and dashboard report dispatch where behavior is identical.
6. Remove unused persistence and Phoenix generator paths only after call-site verification.
7. Correct inaccurate specs, struct access, and high-signal Phoenix/HEEx conventions.
8. Replace duplicated test fixtures with the existing shared fixture module where the tests use the same graph semantics.

## Non-Goals

- Rewrite historical irreversible migrations.
- Change the canonical segment-policy reachability model.
- Add non-unit defense costs or new attacker behavior.
- Remove intentional domain-versus-wire validation boundaries.

## Execution Order

1. Trace every seed, task-failure, and constraint call path; add failing regressions.
2. Apply persistence-safe fixes: seed field alignment, changeset constraints, terminal failure handling, and request error propagation.
3. Align the strategy requirement list and report-fetch reply handling across Phoenix and Svelte.
4. Extract only behavior-identical internal helpers, then delete verified unused code.
5. Normalize the identified specs, struct access, and active Phoenix layout issues.
6. Replace repeated test helpers with `GraphFixtures` or shared test support where no test-specific meaning is lost.
7. Run focused tests after each group, then frontend checks, Terraform health verification, database migrations, and `mix precommit`.

## Completion Criteria

- Generated seeds persist and reload without integer overflow.
- Failed async work marks its record failed and notifies the dashboard.
- Expected uniqueness conflicts return errors rather than escaping transactions.
- Simulation and optimization entry points use one graph-loading/error mapping path.
- The current frontend sends every strategy configuration required by the backend.
- Shared helpers replace duplicated active production code without changing model behavior.
- Removed code has no callers.
- Focused regressions, frontend checks, and `mix precommit` pass.
