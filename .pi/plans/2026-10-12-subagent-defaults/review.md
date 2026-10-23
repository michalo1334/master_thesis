# Code Review

**Reviewed:** Runtime subagent-defaults changes in `pi-fusion` (`21ae9fe..953620d`) and `pi-interactive-subagents`
(`d7a0319..6f94c73`) **Verdict:** APPROVED AFTER FIXES

## Summary

The implementation uses project-local atomic replacement and updates runtime state only after persistence. The launch,
follow-up, resume, and working-directory changes match the intended design in the tested cases.

The initial review found two correctness issues. Commits `953620d` and `6f94c73` resolve them. The findings below remain
as the review record.

## Findings

### [P1 — Resolved] Invalid persisted Fusion model crashed the command instead of reporting an error

**File:** `.pi/git/github.com/michalo1334/pi-fusion/extensions/fusion.ts:547-548`

**Issue:** The handler normalizes the current effective setting before it enters any error handling. A project setting
such as `fusion.sidekickModel: "provider/model:invalid"` is accepted by `readConfig()`, then `normalizeFusionModel()`
throws at line 548. This also happens when the user supplies a complete valid replacement argument. Pi receives a
rejected command handler rather than an actionable notification, and the user cannot use `/fusion-model` to repair the
invalid project setting.

This conflicts with the malformed-input safety and actionable-error requirements. It is especially likely after a manual
edit of the project setting.

**Resolution:** Commit `953620d` moves saved-value normalization into the selector paths that need it. A complete valid
argument can repair an invalid saved value. Selector paths report the invalid value without a write. Production-command
tests cover both cases.

### [P2 — Resolved] The Interactive selector could offer an agent that the persistence resolver could not find

**File:**
`.pi/git/github.com/michalo1334/pi-interactive-subagents/pi-extension/subagents/index.ts:358-364,492-497,2230-2237`

**Issue:** Discovery exposes the frontmatter `name` (`parsed.name`) as the selectable agent identity, but
`resolveAgentSource()` later looks only for a file named `<selected-name>.md`. An agent file whose filename and `name`
differ is therefore listed by `/subagent-model`, but selecting it produces `Agent "..." is not a Pi-backed agent` and no
override. The new command makes this mismatch user-visible.

**Resolution:** Commit `6f94c73` resolves persistence through the same discovered definition used by the selector. It
keeps the source basename for project overrides. Production-command tests cover selector and direct input, and a
persistence test covers a global source with a different basename.

## What's Good

- Fusion persistence writes a sibling temporary file and renames it. It preserves unrelated JSON fields.
- Interactive uses the declared `yaml` dependency and updates the parsed document. Tests cover comments, unknown fields,
  duplicate target keys, malformed YAML, CRLF, and exact body retention.
- Both extensions persist before their runtime selections change.
- Fusion resolves the current model and thinking level immediately before `delegate` and `follow_up`. Follow-ups retain
  their saved session, tools, extensions, timeout, and working directory.
- Interactive preserves explicit model precedence, inherits named-agent thinking for an explicit model without a suffix,
  and leaves legacy resumes without `--model`.
- Fresh Interactive Pi and Claude commands use `effectiveCwd ?? ctx.cwd`; resumes start from `ctx.cwd`. The relative
  tool and named-agent directory policies match the investigation.
- Documentation describes the command syntax, persistence paths, precedence, and resume behavior.
- No new dependency was added to Fusion. Interactive declares `yaml@^2.8.3` directly, as required.
- The only Interactive working-tree change is the pre-existing `package-lock.json` root version change from `1.6.0` to
  `3.7.2`; it was not modified by this review.

## Verification

- `pi-fusion`: `npm test` passed: 126 tests.
- `pi-interactive-subagents`: `env -u PI_DENY_TOOLS npm test` passed: 177 tests.
- The initial Interactive unit-test run inherited
  `PI_DENY_TOOLS=subagent,subagent_interrupt,subagents_list,subagent_resume` from this reviewer child. That
  intentionally suppresses the tools which registration tests expect. This is an environment artifact, not a feature
  regression.
- Interactive integration tests still show the stated baseline failures: the Zellij focus harness lacks its focus
  helpers, and lifecycle waits for its marker. The run then timed out after those failures. I did not classify them as
  regressions.
- `git diff --check` passed for both reviewed ranges.

## Residual Risks and Gaps

- The test suite exercises the production command builders and resolvers, but no end-to-end mux launch test verifies the
  exact fresh-launch command from `launchSubagent()` under the new cwd behavior.
- The suite does not have an explicit command-handler test for a bundled agent whose frontmatter name differs from its
  filename. Bundled agents use the same discovery and basename path as tested project and global agents.
- Atomic replacement does not serialize concurrent writers. This is an accepted plan risk.
