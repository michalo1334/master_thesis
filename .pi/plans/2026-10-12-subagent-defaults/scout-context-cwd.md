# CWD launch investigation

## Scope

This report traces fresh launch, follow-up, and resume paths in:

- `/home/michalo/pi-fusion`
- `/home/michalo/pi-interactive-subagents`
- Pinned Pi API: `/home/michalo/.pi/agent/install/releases/1.1.0/node_modules/@earendil-works/pi-coding-agent`

No source file was changed. No test was run.

## Pinned Pi API evidence

`dist/core/extensions/types.d.ts` defines `ExtensionContext.cwd` as the current working directory. It is separate from
`process.cwd()` and from `ExtensionContext.sessionManager`.

The pinned Pi CLI (`dist/main.js`) sets its initial `cwd` from `process.cwd()`. It creates the runtime and resource
loader with that value. A child process must therefore start with the intended directory before Pi starts, or it will
discover the wrong project resources.

The pinned Pi SDK uses the explicit `cwd` passed to `createAgentSession()` and to `SessionManager.create()`. Fusion uses
both APIs with `ctx.cwd`.

The pinned Pi example at `examples/extensions/subagent/index.ts:272-360` calls `spawn(..., { cwd: cwd ?? defaultCwd })`.
This is the relevant API pattern: use the explicit child directory, then use the parent context directory as the
fallback.

## Fusion trace

### Fresh launch

`/home/michalo/pi-fusion/extensions/fusion.ts:250-285`, `spawnSidekick(ctx, cfg)`:

1. Resolves the model and selected tools.
2. Creates `DefaultResourceLoader({ cwd: ctx.cwd, ... })`.
3. Reloads the loader.
4. Calls `createAgentSession({ cwd: ctx.cwd, ..., sessionManager: SessionManager.create(ctx.cwd) })`.

This passes `ctx.cwd` at every Pi SDK boundary. It does not call `process.cwd()` for launch context. It does not pass a
configuration-directory path as the session cwd.

### Follow-up

`fusion.ts:~340-470`, `runSidekick()` calls `task.session.prompt(message)`. `follow_up` looks up the existing `Task` and
passes its same `AgentSession` to `runSidekick`. No new process or new session is spawned. The original session remains
bound to `ctx.cwd` through its loader and `SessionManager`.

### Configuration paths

`readConfig(ctx.cwd, modelOverride)` reads global settings from `getAgentDir()` and project settings from
`path.join(ctx.cwd, CONFIG_DIR_NAME, "settings.json")`. `selectedExtensionPaths(ctx.cwd, ...)` also resolves project
package paths from `ctx.cwd`. These are resource/config paths, not child launch cwd values.

### Conclusion for Fusion hypotheses

- H1 is **not supported** by the current Fusion source. Fusion does not omit or replace `ctx.cwd` at the SDK launch
  boundary.
- A likely report of Fusion children starting in `/home/.pi` does not match this implementation. The most useful test
  seam is a mocked `createAgentSession`/`SessionManager.create` assertion that both receive a non-process cwd. The
  existing `tests/package.test.ts` only checks package discovery and active tools; it does not exercise `spawnSidekick`
  or assert cwd.
- Follow-up has no independent cwd handoff to fix. It reuses the already-created session.

## Interactive Subagents trace

### Agent definition and default resolution

`pi-extension/subagents/index.ts:297-301` parses `cwd` frontmatter into `AgentDefaults.cwd`.

`index.ts:314` discovers project agents under `join(process.cwd(), ".pi", "agents")`. This is a discovery limitation: it
uses the extension process cwd, not `ctx.cwd`. `loadAgentDefaults()` at `index.ts:404-420` has the same project-agent
lookup order and uses `process.cwd()` for the project path.

`resolveSubagentPaths()` at `index.ts:335-347` does the following:

- Tool parameter `params.cwd` wins.
- Otherwise named-agent `agentDefs.cwd` wins.
- A relative named-agent cwd is based on `getAgentConfigDir()`.
- A relative tool cwd is based on `process.cwd()`.
- With no explicit cwd, it returns `effectiveCwd: null`.
- It chooses session placement from `targetCwdForSession = effectiveCwd ?? ctx.cwd` at `index.ts:1006-1008`.

This preserves the intended named-agent explicit cwd override for session placement and session-header `cwd`. It does
**not** yet produce a shell launch directory for the inherited case.

### Fresh Pi launch

`launchSubagent()` at `index.ts:986-1262` receives `{ ..., cwd: string }` from the extension tool context. At
`index.ts:1006-1008`, it correctly uses `ctx.cwd` as `targetCwdForSession` when no explicit cwd exists. It seeds
lineage/fork sessions with that value at `index.ts:1033-1038`.

The Pi command is assembled at `index.ts:1139-1260`. The critical lines are `index.ts:1229-1232`:

```text
const cdPrefix = effectiveCwd ? `cd ${effectiveCwd} && ` : "";
const piCommand = cdPrefix + envPrefix + parts.join(" ");
```

When no named-agent or tool cwd exists, `effectiveCwd` is null. The generated script has no `cd`. The shell in the new
mux surface then starts in the mux backend's inherited/default directory. The child Pi CLI takes that shell directory as
`process.cwd()`. This explains a child under `/home/.pi` or another configuration directory even though its session
header was seeded with `ctx.cwd`.

When a named agent has explicit `cwd`, `effectiveCwd` is non-null and the generated command begins with
`cd <effectiveCwd> &&`. That override currently works for the Pi path.

The Claude path has the same shape at `index.ts:1093-1094`: it adds `cd` only when `effectiveCwd` exists. The inherited
case is also omitted there.

### Mux launcher path

`pi-extension/subagents/cmux.ts` creates new surfaces with `process.cwd()`:

- `createZellijTiledPane()` around lines 395-396 passes `--cwd process.cwd()`.
- `createZellijStackedPane()` around lines 401-410 passes `--cwd process.cwd()`.
- `createZellijTab()` around lines 413-414 passes `--cwd process.cwd()`.
- WezTerm `createSurfaceSplit()` around lines 850-861 passes `--cwd process.cwd()`.
- Zellij `createSurfaceSplit()` around lines 875-875 passes `--cwd process.cwd()`.
- tmux `createSurfaceSplit()` does not pass `-c`; it inherits the tmux server/pane directory.
- cmux surface creation has no explicit cwd in the inspected calls. A new surface can inherit its pane directory.

`sendLongCommand()` at `cmux.ts:1071-1110` writes a script and sends `bash <script>` to the surface. It does not accept
a cwd and does not change directory. Therefore the mux layer does not repair the missing inherited cwd. It is the nested
launcher identified by H3 only in the sense that it exposes the omission; it does not replace a correct `effectiveCwd`
value because the command itself already contains the explicit `cd` when one exists.

### Resume path

`subagent_resume` is registered at `index.ts:1768-2026`. Its execute handler receives `ctx` at `index.ts:1834` and
builds `pi --session <path>` at `index.ts:1859-1860`.

It propagates `PI_CODING_AGENT_DIR` and subagent metadata at `index.ts:1890-1901`, then builds the command at
`index.ts:1903`:

```text
const command = `${resumeEnvPrefix}${parts.join(" ")}; echo ...`;
```

There is no `cd ctx.cwd` and no mux cwd argument from this handler. Resume therefore starts in the new pane's
current/default directory. The session file can contain the original cwd, but `pi --session <path>` does not change the
shell's `process.cwd()` before startup. This is an independent inherited-cwd gap.

Resume has no named-agent frontmatter input. Its expected default is the parent extension context `ctx.cwd`.

### Follow-up path

Interactive Subagents does not use Fusion's in-process follow-up model. Fresh launches return a `RunningSubagent`; later
work uses `subagent_resume` with a session path and optional message. That resume path has the missing inherited cwd
described above.

## Hypothesis evaluation

| Hypothesis                                                       | Result                | Evidence                                                                                                                                                                                                                |
| ---------------------------------------------------------------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Fusion omits or replaces `ctx.cwd`                               | Not supported         | `fusion.ts:spawnSidekick` passes `ctx.cwd` to `DefaultResourceLoader`, `createAgentSession`, and `SessionManager.create`. Follow-up reuses the session.                                                                 |
| Interactive uses `process.cwd()` or agent definition/config path | Partly supported      | Mux creation uses `process.cwd()`; default launch command uses no `cd`; agent-relative explicit cwd intentionally uses `getAgentConfigDir()`. `ctx.cwd` is used only for session placement, not inherited shell launch. |
| Nested launcher replaces a correct cwd                           | Not the primary cause | `sendLongCommand()` does not set cwd. Mux backends use `process.cwd()` or inherited pane cwd. The primary loss occurs when `effectiveCwd` is null and command generation omits `cd`.                                    |

## Recommended test seams

1. **Pure cwd resolution tests in `test/test.ts`:** cover no explicit cwd, absolute named-agent cwd, relative
   named-agent cwd, and tool-parameter cwd. Assert that named-agent explicit cwd remains based on the agent
   configuration directory, while no explicit cwd resolves to the passed parent context cwd for launching.
2. **Fresh launch command test:** extract or expose a small command-builder seam. Given `ctx.cwd = /project`, assert the
   generated Pi and Claude commands start with `cd '/project' &&` when no override exists. Given agent frontmatter
   `cwd: /other`, assert they start with `cd '/other' &&`, not `/project`.
3. **Resume command test:** build a resume command with `ctx.cwd = /project`; assert it starts with `cd '/project' &&`.
   Assert message-file and environment arguments remain present.
4. **Mux seam test:** avoid testing terminal products for this requirement. Mock `sendLongCommand` or inspect the
   generated stable launch script. The script is the boundary that must contain the directory change.
5. **Fusion SDK seam:** mock `DefaultResourceLoader`, `createAgentSession`, and `SessionManager.create`, or add a small
   exported factory. Assert all cwd values equal `ctx.cwd` and that a follow-up calls `prompt()` on the same session.
6. **Integration test:** launch from a parent whose `process.cwd()` differs from its session context cwd, if Pi can
   create such a context. Have the child write `process.cwd()` and assert it equals the parent context cwd. Run this for
   fresh launch and resume, and for at least one mux backend.

## Plan insertion

### Child launch cwd

The child launch directory has two separate values:

- `targetCwdForSession` already uses `effectiveCwd ?? ctx.cwd` for session metadata and session placement.
- The shell command currently uses `cd effectiveCwd` only when an explicit override exists.

Make the launch command use `effectiveCwd ?? ctx.cwd`. Keep explicit named-agent `cwd` precedence. Apply this to Pi
fresh launch, Claude fresh launch, and `subagent_resume`. Keep session placement and the launch command based on the
same resolved target. Add command-builder tests for inherited and explicit directories. Fusion already passes `ctx.cwd`
through its Pi SDK APIs; add a regression test instead of changing its launch logic.
