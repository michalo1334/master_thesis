# Runtime Subagent Default Selection

**Date:** 2026-10-12 **Status:** Draft **Directory:** `/home/michalo/michalo-common-agent-lib` **Repositories:**
`pi-fusion`, `pi-interactive-subagents`

## Intent

Let users change the default subagent model and thinking level without restarting the current Pi session. Apply the new
values to later launches and persist project-local defaults in each extension's existing configuration format.

Fusion will continue to use JSON settings. Interactive Subagents will continue to use agent Markdown frontmatter. The
feature will not introduce a Fusion agent Markdown format.

## User Story

As a Pi user, I want to change a sidekick or named subagent's default model and thinking level during a session, so that
later tasks use the new defaults without a Pi restart.

## Behavior

### Fusion command

Use the existing command:

```text
/fusion-model [provider/model[:thinking]]
```

- With no argument, show the registered model selector and then the thinking-level selector.
- With a partial argument, prompt for the missing selection.
- With a complete argument, validate and apply it directly.
- Show the effective value and the changed settings path after success.

Persist the normalized value as `provider/model:thinking` in the project `.pi/settings.json` file under
`fusion.sidekickModel`.

### Interactive Subagents command

Add this command:

```text
/subagent-model [agent] [provider/model[:thinking]]
```

- With no arguments, select a discovered Pi-backed agent, model, and thinking level.
- With partial arguments, prompt for missing selections.
- Exclude agents with `cli: claude` from the agent selector.
- Show the effective value and the changed Markdown path after success.

Persist `model` and `thinking` in the selected agent's project Markdown override at `.pi/agents/<agent>.md`.

### Supported thinking levels

```text
off, minimal, low, medium, high, xhigh, max
```

### Happy Path

1. The user runs the applicable command.
2. The command reads the current effective defaults.
3. The user supplies or selects an agent, model, and thinking level.
4. The command validates the selection.
5. The command prepares the updated project file.
6. The command writes a temporary sibling file.
7. The command renames the temporary file over the target.
8. The command updates runtime state.
9. The command confirms the effective value and changed path.
10. A later task starts with the new defaults.

### New tasks

- Fusion delegates resolve the latest Fusion default immediately before launch.
- Interactive agent launches resolve the latest named-agent default immediately before launch.
- An explicit Interactive launch model remains higher priority than a named-agent default.

### Fusion follow-ups

A `follow_up` call resolves the latest Fusion default immediately before launch. It does not reuse the model captured
when the original task started. The task record can retain the value used for diagnostics, but it is not the source of
the next default.

### Interactive resumed sessions

Add an optional `agent` parameter to `subagent_resume`.

- When `agent` is present, resolve that agent's latest model and thinking level and add
  `--model provider/model[:thinking]` to the resume command.
- Include the agent identity in generated resume guidance for new agent-backed sessions.
- When `agent` is absent, retain legacy behavior and do not add a model argument.
- Anonymous subagents have no named default.

### Child launch directory

- Fusion must pass the parent `ctx.cwd` to each Pi SDK launch boundary. Follow-ups reuse the same bound session.
- Interactive fresh Pi and Claude launches must use `effectiveCwd ?? ctx.cwd` as the shell launch directory.
- Interactive resumes must use the current parent `ctx.cwd` as the shell launch directory.
- An explicit named-agent or tool `cwd` remains higher priority than the parent directory.

### Errors and cancellation

- A cancelled selector makes no change.
- Invalid models make no change.
- Invalid thinking levels make no change.
- A failed persistence operation leaves runtime state unchanged.
- A malformed Fusion settings file is reported and not overwritten.
- Missing or malformed agent frontmatter is reported and not replaced.
- Duplicate `model` or `thinking` keys are reported and not changed.
- A source agent that disappears during the command produces an error.
- A read-only project target produces an error that includes the path.
- An unavailable persisted model produces the existing launch error. The extension does not rewrite the selection
  automatically.

## Scope

### In Scope

- Extend `/fusion-model` with thinking-level selection.
- Persist Fusion defaults in project `.pi/settings.json`.
- Add `/subagent-model` for named Pi-backed agents.
- Persist Interactive defaults in project agent Markdown.
- Update in-memory defaults after successful persistence.
- Apply current defaults to new tasks.
- Apply current Fusion defaults to follow-ups.
- Apply current named-agent defaults to agent-backed resumes.
- Inherit the parent working directory for fresh and resumed child launches.
- Preserve explicit agent and tool working-directory overrides.
- Preserve unrelated JSON settings.
- Preserve unrelated Markdown frontmatter.
- Preserve the Markdown prompt body.
- Preserve Markdown line endings.
- Add direct tests for parsing, persistence, precedence, follow-ups, and resumes.
- Update both READMEs.
- Update Fusion's skill instructions.

### Out of Scope

- Editing Fusion's TypeScript fallback at runtime.
- Moving Fusion configuration from JSON to Markdown.
- Changing a child process that is already running.
- Restarting children after a default change.
- Adding a callable configuration tool.
- Changing defaults for Claude-backed Interactive agents.
- Passing thinking levels to Claude CLI.
- Adding full YAML parsing for agent frontmatter.
- Adding file locks for concurrent writers.
- Updating anonymous or legacy resumes that have no agent identity.
- Modifying the pre-existing Interactive `package-lock.json` change.

## Effort and Quality

- **Level:** MVP
- **Tests:** Thorough
- **Documentation:** Both project READMEs and Fusion's skill instructions

## Constraints

- Keep each repository independent. Do not add a shared package.
- Use each repository's pinned Pi extension API.
- Fusion uses `@earendil-works/pi-coding-agent` APIs.
- Interactive Subagents uses `@mariozechner/pi-coding-agent@0.65.0` APIs.
- Both APIs expose model registry lookup and UI selection, but their context types differ.
- Interactive's context does not expose a current thinking-level field.
- Use a fixed thinking-level list in both commands.
- Preserve existing direct launch overrides.
- Do not edit bundled or global agent Markdown files.
- Do not overwrite unrelated working-tree changes.

## Precedence

### Fusion

During the current Pi session:

```text
current session selection
→ PI_FUSION_MODEL
→ project .pi/settings.json
→ global settings
→ package fallback
```

After a Pi restart, runtime state is empty. Normal file and environment resolution applies. `PI_FUSION_MODEL` can
override the persisted project value until the user runs `/fusion-model` again.

### Interactive Subagents

```text
explicit launch model and optional thinking suffix
→ current named-agent session selection
→ project agent Markdown
→ global agent Markdown
→ bundled agent Markdown
→ Pi default
```

If an explicit model includes a thinking suffix, both explicit values win. If it has no thinking suffix, the current
named-agent thinking default applies.

## Ideal State Criteria

### Commands

- [x] **ISC-1:** `/fusion-model` changes the Fusion model without restarting Pi.
- [x] **ISC-2:** `/fusion-model` changes the Fusion thinking level without restarting Pi.
- [x] **ISC-3:** `/subagent-model` lists discovered Pi-backed agents.
- [x] **ISC-4:** `/subagent-model` changes the selected agent's model.
- [x] **ISC-5:** `/subagent-model` changes the selected agent's thinking level.

### Persistence

- [x] **ISC-6:** Fusion writes its selection to project `.pi/settings.json`.
- [x] **ISC-7:** Interactive Subagents writes a project agent Markdown override.
- [x] **ISC-8:** Markdown updates preserve the agent prompt body.
- [x] **ISC-9:** Markdown updates preserve unrelated frontmatter fields.
- [x] **ISC-10:** JSON updates preserve unrelated settings.
- [x] **ISC-11:** Bundled agent definitions remain unchanged.
- [x] **ISC-12:** Global agent definitions remain unchanged.

### Runtime behavior

- [x] **ISC-13:** New tasks use the latest selected defaults.
- [x] **ISC-14:** Fusion follow-ups use the latest selected defaults.
- [x] **ISC-15:** Agent-backed Interactive resumes use the latest selected defaults.
- [x] **ISC-16:** Explicit launch model arguments override stored defaults.
- [x] **ISC-17:** Successful writes update runtime state immediately.
- [x] **ISC-17a:** Fusion SDK launch boundaries receive the parent `ctx.cwd`.
- [x] **ISC-17b:** Interactive fresh launches use `effectiveCwd ?? ctx.cwd`.
- [x] **ISC-17c:** Interactive resumes start from the parent `ctx.cwd`.
- [x] **ISC-17d:** Explicit Interactive `cwd` values override the parent directory.

### Error handling

- [x] **ISC-18:** Invalid models leave persisted configuration unchanged.
- [x] **ISC-19:** Invalid thinking levels leave persisted configuration unchanged.
- [x] **ISC-20:** Failed writes leave runtime defaults unchanged.
- [x] **ISC-21:** Invalid agent frontmatter produces an actionable error.
- [x] **ISC-22:** Duplicate `model` keys produce an actionable error.
- [x] **ISC-23:** Duplicate `thinking` keys produce an actionable error.
- [x] **ISC-24:** A missing source agent file produces an actionable error.

### Tests and documentation

- [x] **ISC-25:** Automated tests cover command registration in both repositories.
- [x] **ISC-26:** Automated tests cover runtime default changes.
- [x] **ISC-27:** Automated tests cover persisted configuration changes.
- [x] **ISC-28:** Automated tests cover follow-up model replacement.
- [x] **ISC-29:** Automated tests cover agent-backed resume model replacement.
- [x] **ISC-30:** Both READMEs document the new command behavior.
- [x] **ISC-31:** Fusion's skill documentation describes `/fusion-model`.

### Anti-Criteria

- [x] **ISC-A1:** No running child is restarted or modified.
- [x] **ISC-A2:** No bundled agent Markdown file is modified.
- [x] **ISC-A3:** No global agent Markdown file is modified.
- [x] **ISC-A4:** No callable configuration tool is added.
- [x] **ISC-A5:** No unrelated `package-lock.json` change is overwritten.

## Approach

Use extension-local configuration helpers. Both extensions follow the same behavioral contract, but each keeps its
existing persistence format and Pi API dependency.

### Key Decisions

- Keep `/fusion-model` because Fusion already exposes it.
- Add `/subagent-model` because Interactive Subagents has no default-selection command.
- Store Fusion values in project JSON because that is its current configuration system.
- Store Interactive values in project agent Markdown because model and thinking already belong to agent definitions.
- Persist before changing runtime state to prevent memory and disk disagreement.
- Resolve defaults at launch time so later tasks use current values.
- Use the latest default for Fusion follow-ups.
- Use the latest default for agent-backed Interactive resumes.
- Keep legacy resume behavior when agent identity is absent.
- Restrict `/subagent-model` to Pi-backed agents because Claude models are outside Pi's registry and Claude thinking is
  not passed by the current launcher.

## Architecture

### Fusion components

1. **Selection parser**
   - Parse and normalize `provider/model[:thinking]`.
   - Validate the model through the Fusion model registry.
   - Validate thinking through the fixed list.

2. **Project settings writer**
   - Read `<cwd>/.pi/settings.json`.
   - Create the file or `fusion` object when absent.
   - Replace only `fusion.sidekickModel`.
   - Preserve unrelated settings.
   - Use temporary-file replacement.

3. **Runtime default state**
   - Store the successful session selection.
   - Give it precedence over environment and file defaults in the current session.

4. **Launch resolver**
   - Serve both `delegate` and `follow_up`.
   - Resolve immediately before each launch.

### Interactive Subagents components

1. **Agent discovery metadata**
   - Return the effective definition and source path.
   - Mark the source as project, global, or bundled.
   - Exclude `cli: claude` agents from `/subagent-model` selection.

2. **Frontmatter reader and writer**
   - Locate the first frontmatter block.
   - Detect duplicate target keys.
   - Copy the effective definition when a project override does not exist.
   - Replace or add `model` and `thinking` fields.
   - Preserve unrelated fields, body text, and line endings.
   - Parse the generated result before final replacement.

3. **Runtime defaults map**
   - Key entries by agent name.
   - Commit entries after successful persistence.

4. **Command handler**
   - Select the agent, model, and thinking level.
   - Persist the project override.
   - Confirm the effective value and path.

5. **Launch resolver**
   - Serve initial agent launches and agent-backed resumes.
   - Preserve explicit model precedence.

6. **Resume identity**
   - Add an optional `agent` field to `subagent_resume`.
   - Include the field in generated resume guidance.
   - Add the current named-agent model argument only when identity is present.

## Data Flow

### Configuration change

```text
command input or selector
→ parse
→ registry validation
→ thinking validation
→ prepare complete file content
→ write temporary sibling
→ rename target
→ update runtime state
→ notify user
```

### Child launch

```text
launch request
→ identify Fusion or named Interactive agent
→ resolve current defaults
→ apply explicit launch override
→ build child command
→ launch child
```

### Fusion follow-up

```text
follow_up request
→ locate task session
→ resolve current Fusion default
→ launch against saved session
→ record value used for diagnostics
```

### Interactive resume

```text
subagent_resume request
→ validate session path
→ read optional agent identity
→ resolve latest named-agent defaults when present
→ add --model provider/model[:thinking]
→ resume saved session
```

## Dependencies

No new runtime package is required.

Use existing facilities:

- Node file-system and path APIs
- Each repository's Pi model registry
- Each repository's `ctx.ui.select()` and notification APIs
- Existing command registration
- Existing child launch and resume paths
- Existing TypeScript ESM and `node:test` setup

## Test Strategy

### Fusion

- Test command registration expectations.
- Test no-argument model and thinking selection.
- Test direct complete arguments.
- Test partial arguments.
- Test JSON creation.
- Test preservation of unrelated JSON settings.
- Test malformed JSON failure.
- Test failed-write runtime rollback.
- Test runtime precedence over `PI_FUSION_MODEL`.
- Test new delegates use the latest value.
- Test follow-ups use the latest value.
- Test invalid model and thinking rejection.

### Interactive Subagents

- Test command registration expectations.
- Test Pi-agent filtering.
- Test Claude-agent exclusion.
- Test project override creation from bundled and global definitions.
- Test update of an existing project definition.
- Test preservation of prompt text and unrelated fields.
- Test line-ending preservation.
- Test missing frontmatter.
- Test duplicate target keys.
- Test missing source files.
- Test read-only or injected write failure.
- Test explicit launch precedence.
- Test new launches use runtime defaults.
- Test agent-backed resumes add the latest model and thinking.
- Test legacy resumes omit a new model argument.
- Test fresh Pi and Claude launch commands inherit `ctx.cwd` when no override exists.
- Test explicit agent and tool working directories remain higher priority.
- Test resume commands start from `ctx.cwd`.
- Test production helper functions directly instead of duplicating their logic in tests.

### Fusion launch-directory regression

- Test that Fusion passes `ctx.cwd` to its Pi SDK resource loader and session factories.
- Test that follow-ups reuse the original session instead of starting in a new directory.

### Repository safety

- Run each repository's existing test suite separately.
- Inspect each repository's final diff.
- Verify that Interactive Subagents' pre-existing `package-lock.json` change remains untouched.

## Documentation

### Fusion README and skill

Document:

- `/fusion-model` syntax
- interactive selectors
- project settings path
- session and restart precedence
- new-task behavior
- follow-up behavior
- failure behavior

### Interactive Subagents README

Document:

- `/subagent-model` syntax
- Pi-backed agent restriction
- project override path
- copied-override behavior
- explicit launch precedence
- `subagent_resume.agent`
- legacy resume behavior
- new-task and resumed-session behavior

## Risks and Open Questions

### Mitigated risks

- **Partial writes:** Use temporary-file replacement.
- **Runtime and disk disagreement:** Persist before runtime commit.
- **API mismatch:** Keep repository-specific adapters and tests.
- **Incorrect test coverage:** Export or isolate production helpers for direct testing.
- **Unrelated changes:** Exclude and verify the existing Interactive lockfile modification.
- **Resume behavior:** Test `--model` against the pinned Interactive Pi version.

### Accepted risks

- A copied bundled or global agent becomes a full project override. Later upstream prompt changes do not reach that
  project file automatically.
- A legacy resume without agent identity keeps the session's existing model.
- Concurrent external writers are not locked. The command reads immediately before writing to reduce stale updates.
- Full YAML syntax is not supported. The writer supports the repository's existing simple scalar frontmatter format.
- A persisted model can become unavailable after selection. Launch then reports the normal model-resolution error.

### Open questions

None. The user accepted the command surfaces, project-local persistence, precedence, latest-default follow-up and resume
behavior, Pi-only Interactive scope, architecture, edge cases, and risk treatment.
