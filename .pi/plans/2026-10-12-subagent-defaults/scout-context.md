# Context for: switch and persist default subagent model and thinking level

## Relevant Files

### pi-fusion

- `.pi/git/github.com/michalo1334/pi-fusion/extensions/fusion.ts` — Main extension. Defines `FusionConfig`, hard-coded
  `DEFAULTS`, JSON `readConfig()`, model/thinking parsing, `/fusion-model`, and `delegate`/`follow_up` tools.
- `.pi/git/github.com/michalo1334/pi-fusion/extensions/child-runner.ts` — Child process boundary. `ChildModel` includes
  `provider`, `id`, and `thinking`; launch arguments are built here and the selected model is passed into child runtime.
- `.pi/git/github.com/michalo1334/pi-fusion/extensions/child-process.ts` — Lower-level child command construction and
  `--model`/`--thinking` argument handling used by the child runner.
- `.pi/git/github.com/michalo1334/pi-fusion/extensions/child-runtime.ts` — Runtime policy/child extension entry point;
  relevant to how child Pi processes receive model state.
- `.pi/git/github.com/michalo1334/pi-fusion/tests/fusion-follow-up.test.ts` — Existing harness for loading the
  extension, settings-based Fusion configuration, and verifying delegate/follow-up model behavior.
- `.pi/git/github.com/michalo1334/pi-fusion/tests/package.test.ts` — Package discovery smoke tests. It currently expects
  one extension, `delegate`/`follow_up`, and only the `fusion-model` command.
- `.pi/git/github.com/michalo1334/pi-fusion/README.md`, `skills/fusion/SKILL.md` — User-facing configuration and
  delegation documentation.

### pi-interactive-subagents

- `.pi/git/github.com/michalo1334/pi-interactive-subagents/pi-extension/subagents/index.ts` — Nearly all extension
  logic. It defines `AgentDefaults`, frontmatter parsing/discovery, in-memory `runningSubagents`, subagent launch
  command construction, tools, and `/iterate` and `/subagent` commands.
- `.pi/git/github.com/michalo1334/pi-interactive-subagents/agents/*.md` — Bundled Markdown agent definitions.
  Frontmatter currently carries `model`, `thinking`, tools/skills, lifecycle, and session settings. `worker.md` uses
  `model: openai/gpt-5.6-terra` and `thinking: minimal`; `scout.md` uses `model: openai/gpt-5.6-luna` and
  `thinking: ...`.
- `.pi/git/github.com/michalo1334/pi-interactive-subagents/test/system-prompt-mode.test.ts` — Standalone tests that
  duplicate frontmatter parsing/routing logic and exercise temporary Markdown agent files.
- `.pi/git/github.com/michalo1334/pi-interactive-subagents/test/integration/subagent-lifecycle.test.ts` and
  `test/integration/mux-surface.test.ts` — Multiplexer/launch lifecycle integration coverage.
- `.pi/git/github.com/michalo1334/pi-interactive-subagents/README.md` — Documents the three current commands and agent
  Markdown discovery/override priority.
- `.pi/git/github.com/michalo1334/pi-interactive-subagents/config.json.example` — Status widget configuration only; it
  does not contain agent model defaults.

## Project Structure and Repository State

The parent project is `michalo-common-agent-lib`; it contains vendored Pi package repositories under
`.pi/git/github.com/...`. Both requested repos are independent Git working copies, not symlinks and not submodules:

- `.pi/git/github.com/michalo1334/pi-fusion` — remote `https://github.com/michalo1334/pi-fusion`, branch `main`, clean,
  at `9ab09cb`.
- `.pi/git/github.com/michalo1334/pi-interactive-subagents` — remote
  `https://github.com/michalo1334/pi-interactive-subagents`, branch `main`, at `3c47481`; it has a pre-existing modified
  `package-lock.json`.

There is also a separate `.pi/git/github.com/HazAT/pi-interactive-subagents` checkout and other copies elsewhere under
`/home/michalo`. The active path in this project is the `michalo1334` checkout. The package repositories have their own
`package.json`, lockfile, tests, and TypeScript source; they are not part of the parent package build.

## Runtime State and Current Model/Thinking Behavior

### pi-fusion

`FusionConfig` currently has:

- `sidekickModel: string`, default `anthropic/claude-sonnet-4-6:high`.
- `timeoutMinutes`, `sidekickTools`, and `sidekickExtensions`.

`readConfig(cwd, modelOverride)` starts from defaults, reads global then project `.pi/settings.json`
(`getAgentDir()/settings.json` and `cwd/.pi/settings.json`), applies `json.fusion`, then `PI_FUSION_MODEL`, then the
process-local `modelOverride`. It does not read or write Markdown. The `modelOverride` variable is closure-local to
`createFusionExtension`, so it disappears on extension/session reload. Settings JSON is the only persistent source
today.

`resolveSidekickModel()` expects `provider/model[:thinking]`, defaults thinking to `off`, validates thinking against
`off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, and resolves the base model through `ctx.modelRegistry`. The
resolved object is converted to `{ provider, id, thinking }`. `delegate` resolves config at launch time and stores that
model in its `ChildTask`; follow-up reuses the task's stored model, so changing the default cannot retroactively change
an existing task.

The only current UI/command is `/fusion-model`. With no argument it offers provider/model selection and stores only a
process-local override (the selector does not expose thinking). With an argument it validates and stores a
`provider/model[:thinking]` string in the same process-local variable. It notifies “for this Pi process/session” but
does not persist it. There is no separate thinking state or command.

### pi-interactive-subagents

`AgentDefaults` includes optional `model`, `thinking`, `tools`, `skills`, lifecycle/session flags, `cwd`, and CLI
fields. `parseAgentDefinition()` recognizes a simple `---` frontmatter block and extracts values with line-based
regexes; it retains the body as the system prompt. `discoverAgentDefinitions()` merges package, global, and project
`.pi/agents` directories in that order, so later global/project entries overwrite earlier names. `loadAgentDefaults()`
selects project-local first, then global, then bundled (a different priority order for a named lookup).

`launchSubagent()` resolves `effectiveModel = params.model ?? agentDefs?.model`; it resolves
`effectiveThinking = agentDefs?.thinking` only (there is no tool parameter for thinking). For Pi-backed children it
passes `--model` as `model:thinking` when both are present. For Claude-backed children it passes only `--model`;
thinking is not passed to Claude. If no model is available, Pi receives no explicit model and uses its own default. A
model override can therefore replace the Markdown model, but it cannot independently override Markdown thinking through
the current public tool schema.

The extension has four tools (`subagent`, `subagent_interrupt`, `subagents_list`, `subagent_resume`) and three commands
(`/plan`, `/iterate`, `/subagent`). None changes agent defaults. `/subagent <agent> [task]` loads the named Markdown
definition, then sends a synthetic user message that invokes the `subagent` tool. `runningSubagents` is a module-level
map; it tracks active launch/session/status data, but no mutable default model/thinking state exists. Session start only
stores the latest UI context and starts polling.

## Markdown Configuration

The relevant Markdown configuration is the agent definition file, normally `<agent-config-dir>/agents/<name>.md` or
project `.pi/agents/<name>.md`; bundled files live in `pi-interactive-subagents/agents`. Frontmatter fields are simple
scalar `key: value` lines bounded by `---`. Existing agent files use this form, including `model:` and `thinking:`.
There is no Markdown parser/writer abstraction and no current write path. Any persistence feature will need to preserve
the body and unrelated frontmatter, account for project/global/package precedence, and decide which named file is
authoritative.

pi-fusion does not currently use agent Markdown for its sidekick default. Its relevant persisted configuration is JSON
(`.pi/settings.json` under a `fusion` key), while its bundled skill is Markdown but is not configuration. This is an
important mismatch with the request to persist in the “relevant Markdown configuration file”: the planner must define
whether Fusion should adopt a Markdown agent/default file or whether the request refers only to interactive-subagents’
agent files.

## Tests and Conventions

- Both packages use TypeScript ESM and Node’s built-in `node:test` (Fusion: `node --test tests/*.test.ts`;
  interactive-subagents: `node --test test/test.ts`, with separate integration tests).
- Tests use temporary directories, hand-built extension/API seams, `assert/strict`, and fixture files. Fusion tests
  inject `runChildTask`, model registry, and settings. Interactive tests often duplicate small parsing/routing helpers
  rather than importing private functions.
- Existing package smoke tests assert exact command/tool registration, so adding commands requires updating those
  expectations.
- Code style uses 2-space indentation, semicolons, double-quoted strings, and explicit TypeScript interfaces. Errors are
  reported through `ctx.ui.notify` for commands and thrown/returned from tools.
- Existing Markdown frontmatter parsing is intentionally minimal: regex matching, no YAML dependency, no
  escaping/quoting support beyond the scalar line match. No tests cover malformed duplicate keys, comments, multiline
  values, or write preservation.

## Key Findings for Planning

1. Fusion already has a runtime model selection command, but its state is ephemeral and its model string combines model
   and thinking. Its default is re-read for every new `delegate`; follow-up uses the model captured in the task.
2. Interactive-subagents already models agent defaults in Markdown and applies `model:thinking` at Pi launch, but has no
   runtime mutation command and no persistence writer.
3. The two projects have different host package peer versions (`@earendil-works/...` in Fusion versus
   `@mariozechner/...` in interactive-subagents), so extension API assumptions and command/UI implementations should be
   checked separately.
4. To work “without reloading the session”, a command must update in-memory defaults used by later launches and write
   the selected values immediately. Existing running child processes cannot be changed by a default mutation; only later
   launches (and possibly explicitly resumed launches, depending on design) can observe it.
5. Model availability validation differs: Fusion validates via `ctx.modelRegistry` before changing its override;
   interactive-subagents currently accepts the Markdown/tool model string and lets the child CLI resolve it. Thinking
   validation is explicit in Fusion but absent in interactive-subagents.
6. A persistence implementation must avoid losing unrelated frontmatter/body content and must define behavior when the
   selected file is bundled/read-only, absent, shadowed by project/global precedence, or contains invalid frontmatter.
