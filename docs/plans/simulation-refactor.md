# Simulation Refactor

1. Store the master seed and iteration configuration on experiments.
2. Derive one integer seed per run, initialize the PRNG once, and keep its state in memory only.
3. Serialize concrete actions, attempted-action counts, and attacker state with embedded schemas.
4. Select one eligible action at random per iteration. Exclude an action after its configured attempt limit.
5. Keep matched edge IDs on actions as provenance so successful attempts still drive edge-traversal reports.
6. Replace obsolete simulation columns in a fresh-schema migration and discard prior simulation history.
7. Update callers, persistence, reports, and tests. Verify with migrations and `mix precommit`.
