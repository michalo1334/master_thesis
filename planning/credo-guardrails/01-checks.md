# Chunk 1: checks, tests, and profiles

Implement the five checks specified in design.md. Work only in this worktree. Read the existing check and test before changes.

Add custom files under src/credo/checks/ and focused tests under src/test/network_defense/credo/. Use the established Context/SourceFile APIs for the locked Credo version. Prefer explicit small recursive AST visitors over macro expansion. Test reported line numbers, quote exclusions, matching and nonmatching module scope, and literal shapes. Cover grouped aliases and explicit Elixir-qualified names where the rules promise them. If dynamic/module-alias resolution would require a general analyzer, exclude and document that form.

Update src/.credo.exs to require the files and enable the three strong and two advisory checks. Add project_strong and project_heuristics profiles without duplicating the entire generated config. Keep default existing checks unchanged except the additions. Use exit_status: 0 for heuristics and verify Credo honors it. Profiles should scan relevant production sources, not test fixture strings. Default test scanning must not misclassify embedded quoted snippets.

New tests should also run without PostgreSQL or booting the application. Choose a small explicit test-runner command or script that loads only the new tests and Credo; do not weaken the existing mix test alias or the error-code check. Wire that focused verification into CI/precommit if needed so it cannot drift unrun. Avoid a new dependency. If a DB-free mix test command already works, prefer it.

Run relevant tests and formatting. Capture output. Exercise the profiles against disposable CLI fixtures for a failing strong case and a visible-but-successful heuristic case. Run profiles on the repository, record and inspect every new finding. Do not change application code just to eliminate a heuristic. Keep any legitimate findings visible and explain their limits in your report.

Do not commit. The parent will inspect the actual changes and write final usage/verification documentation. Return exact commands, exit codes, file paths, findings, and unresolved gaps. If environment setup prevents verification, report it promptly and continue only work that remains defensible.
