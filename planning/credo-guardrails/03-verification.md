# Chunk 3: real execution evidence

You are a command-runner subagent. Work only in /tmp/master-thesis-credo-guardrails. No code edits or commits unless the parent approves.

The corrected checks have only direct smoke evidence because this worktree has no src/deps. The earlier agent used shared dependency paths and its green claims are superseded. Get real locked dependencies into this worktree with MIX_ENV=test mix deps.get. Do not set MIX_DEPS_PATH to the primary checkout. Use bounded scheduler counts if needed to avoid resource contention. Capture all command statuses.

Run:
- mix credo.test (with no externally set MIX_ENV, verifying preferred env works);
- MIX_ENV=test mix format --check-formatted for changed Elixir files;
- MIX_ENV=test mix credo --strict;
- MIX_ENV=test mix credo -C project_strong;
- MIX_ENV=test mix credo -C project_heuristics.

For EACH of the three strong checks and BOTH heuristics, run realistic full-module CLI fixtures at matching virtual/file paths via the real profiles. Verify the intended check name/message and line, not merely exit code. Strong => nonzero; heuristic => visible finding, zero. Keep disposable fixtures out of tracked source and remove them after the test. Include nonmatching controls for throw catches, unqualified/dynamic aliases, and non-LiveView Repo usage.

Run the focused tests through normal mix test discovery too, including the existing error-code check, if possible. Use a NEW isolated PostgreSQL container on an unused loopback port, with test-only trust auth confined to that disposable resource (no real secret required), and REPO_PORT override. Never use an existing development DB. Capture startup and test outcomes; remove only the new disposable test container after work. If full test discovery requires built frontend manifests, report this and build only in this worktree (npm ci + mix assets.build) if resources permit. Do not change source to bypass failed tests.

Review new real repository findings. Expected advisory candidates include cleanup catch clauses returning :ok; keep them visible, with explanations. Existing lint debt is not automatically a failure of new rules, but record it exactly rather than claiming the default gate passed.

Save a durable concise report to planning/credo-guardrails/verification.md with exact commands, exit statuses, counts, finding classifications, scope and limitations. Raw logs may go under planning/credo-guardrails/logs/ but do not commit giant dependency/build logs or secrets. Parent writes final usage docs and decides commit scope.
