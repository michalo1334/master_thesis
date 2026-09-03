# Info

A system for modeling and applying defenses (minimizing blast radius) in computer networks.

SEE README.md FIRST

## General workflow

Your agent type:
- main agent if the prompt doesn't contain any info
- subagent if prompt specifies it

Whenever you invoke/delegate to subagent always in prompt specify the subagent delegated to is a subagent.

General workflow is as follows:
- always use `explorer_fast` model for exploring and review, never `Explorer`
- use `implementor_fast` for implementation
- when you are the main agent your responsibility is general thinking/approaching the problem and orchestrating subagents. For exploration and implementation use subagents as much as possible Pass context (including those from subagents) to subagents via temporary markdown files. You can do small fixes or quick pass reviews.
- split plan (designed during planning mode) into reasonably small but logical chunks (e.g. BE chunk, FE chunk OR BE + FE chunk, vertical slice style). Handoff each chunk to implementation subagent along with relevant context


## Plan mode / plan preparation:

### Plan format

Plan is split into two parts:
- the design - high and medium level overview, does not describe HOW to execute and what steps to follow, only the overall idea/introduction to the problem being solved
- the execution - step by step execution, refers back to design points. Missed detail in the design is done here.

### Design part/m

Visualize the change, do not write only dry bullet points of TODOs without further elaboration.

Use diagrams for difficult to imagine or describe with plain language - architectural, flow (functionality, communication), C4. Do not add diagrams if they only introduce noise or the text is clear enough. Code examples for usage (e.g. if it's library or reusable component) and interface declaration (function signatures, file or wire formats, classes and methods).

Use other visualization methods that could be more suitable than the described above.

**Principle:** visualize the change. Think Edward Tufte, Envisioning Information and related books not as guide to literally use what is described there but as principle.

#### Testing
Design contains one-liner test cases in EARS notation. Do not write test cases OR regression tests for things that can be checked more efficiently and more generically with other methods. Use other methods to keep things in check like logging, manual tests, IaC, static analysis (Credo) etc.

**Never** use real-code values 1:1 in test cases. The values can be similar structurally.


#### Other but important

Prioritize minimal changes (see `pony`) but if requested, design in mind of scalability later.

Security.

### Execution part

Split into bite-sized, logically coherent chunks worth of around 30min-1h of human effort. Delegate each chunk into subagents, default one is `implementor_fast_fast`, unless overriden by the user.
Each chunk should be pre-written to file first.
 
Chunks should contains as much context as possible from you - subagents are tabula rasa beside the repository basic info, the main plan and execution chunk.

**IMPORTNANT REGARDING SUBAGENT PROMPT PASS**: To improve token caching via prefix prompt caching, all implementor subagents must have the same common part, that is:

1. Design plan file reference
2. Execution chunk file reference
3. Common, additional instructions (write this to file) file reference!. Additional instructions are design specific, common for all chunks
3. Additional, specific instructions from you

The prefix **MUST** be 1:1, even one newline or word in different order will break cache.

After every step perform quick code review to check if changes are coherent with the design and plan. Blockers or unforseen obstacles (like we assumed X but turns out is Y) **must** be reported to the user.

## Documentation

- For interacting with user (this includes also your output regardless of mode) and/or writing documentation (in general) use `writing-clearly-and-concisely` skill.
- For writing *technical* documentation or acting as subagent (output) *always* use `asd-ste100` skill.
- Always use Mermaid for diagrams, including those embedded inside markdown blocks. See `mermaid-diagrams` for reference. Do not use ASCII art or other languages like PlantUML unless expliticly specified by the user
- Never copy paste source code or concrete values unless is for example purposes. It gets outdated very quickly. Instead point to relevant file/place for current values. The point is that documentation can get out of sync with aspects that change dynamically like source code
- Do not document what can be read from the config or source code. Document why, not what.
- Documentation files verbosity: Imagine you are lazy engineer who prefers doing useful work and hates absolutely documentation. Document absolute bare minimum, do not over explain. Brief sentences. If explanation is unclear, follow up with example (can be complex one) in elixir or pseudocode

## Command invocation

Many command outputs have very verbose outputs, therefore there is dedicated `cmd_runner` agent for running them and outputting brief summary and errors/warnings. Delegate command invocation (or command chain) for following ones:

- Terraform
- Any build, test, linter, format
- Querying anything BUT SQL e.g. Loki, Tempo endpoints but not limited to them
- playwright-cli
- git operations (including commit, status)
- any tools or other commands that you find out have verbose output during the workflow. Write them down to file `verbose_tools.md` with bullet points and brief reason why

## Infrastructure

Project uses Terraform for provisioning infrastructure - `/infra`.

Local environment module contains helper script that preloads local `.env` file. Use it for using Terraform locally - `/infra/environments/local/terraform.sh`

### Observability

Loki, Tempo and Promethesus are used for storing telemetry data.

### Secrets & inputs

To provide agnostic way of passing inputs and secrets, use two mechanisms: 

 - for non-sensitive inputs **environment variables**
 - for secrets **files** that have restrictive permissions or mounted into container

Good:
 - using .env for local development (gitignored!)
 - using secret managers (AWS, Hashicorp etc) to fetch state into files 
 - using sidecar or scripts that fetch vars right before starting the stack

Bad
 - hardcoding values passed in e.g. docker compose
 - "ifology" inside app (provider or SDK specific)

To discuss with user
 - "common defaults" like well-known service ports or port mappings (e.g. Grafana, PostgresSQL)

## Frontend

- Follow the conventions established in codebase
- For new components use bits-ui
- BE defined types contracts must match between frontend and backend (contracts/ directories)

## Post Completion Check of tasks

ALWAYS, THIS IS NOT NEGOTABLIE, POST CHECK your results. Fix? test it, query the db, check logs, check if the fix didn't broke anything else and actually worked.
