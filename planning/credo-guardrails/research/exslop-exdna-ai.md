# ExSlop, ExDNA, and AI-code evidence

Research used a parallel explorer agent with `openai-codex/gpt-6-luna`. The main agent compiled this report. Package-source inspection, upstream browsing, measured research, and recommendations are distinguished below.

## Two different tools

The application declares `ex_slop` and locks version 0.4.4. The inspected local package describes 40 Credo checks and declares an MIT license. Its source is [elixir-vibe/ex_slop](https://github.com/elixir-vibe/ex_slop). The current upstream release was not independently established.

The user-supplied URL points to [elixir-vibe/ex_dna](https://github.com/elixir-vibe/ex_dna), a separate duplication analyzer used by ExSlop. Its browsed repository exposes an MIT license, source, tests, and workflows. This pass did not inspect enough upstream test bodies to judge their coverage.

ExSlop's inspected package groups checks into:

- Seven warnings: broad rescue, log-without-reraise rescue, query-in-map, load-then-filter, GenServer-as-map, `priv` path handling, and atom/string fallback keys.
- Twenty-six refactoring checks: redundant transformations and recognizable Enum, List, string, and exception-handling patterns.
- Seven readability checks: narrator comments, numbered steps, boilerplate docs, and related presentation patterns.

Representative local source paths are `src/deps/ex_slop/lib/ex_slop/check/warning/blanket_rescue.ex`, `warning/query_in_enum_map.ex`, and `refactor/try_rescue_with_safe_alternative.ex`. These are dependency-cache paths, not committed project artifacts. Consult the package pinned in `src/mix.lock` when reproducing the inspection.

The implementation uses ordinary Credo AST predicates. It is not an authorship classifier. The README recommends a subset and makes noisier checks opt-in. Its “high-signal” label is not a published precision measurement. Explicit Credo check lists can override plugin registration, so configuration must be tested, not assumed.

ExDNA describes exact, renamed/literal-variant, and near-miss structural clones. It supports minimum mass, occurrence thresholds, exclusions, macro exclusions, pipe normalization, and similarity thresholds. Its Credo integration replaces Credo's duplicate-code check and claims to reuse parsed ASTs. Clone candidates still need a semantic review: separate policies or fixtures can intentionally resemble each other.

## Internet evidence about AI mistakes

[Perry et al., *Do Users Write More Insecure Code with AI Assistants?*](https://arxiv.org/abs/2211.03622) report a controlled study of security-related programming tasks across languages. Participants with a Codex-davinci-002 assistant produced less secure code on average and more often believed their code was secure. The evidence concerns that model, tasks, and participants. It does not show that every current assistant is less secure, or that a particular syntax identifies AI output.

A second primary source gives a concrete cross-language mistake class: [Spracklen et al., *We Have a Package for You!* (USENIX Security 2025)](https://www.usenix.org/system/files/usenixsecurity25-spracklen.pdf), also indexed as [arXiv:2406.10279](https://arxiv.org/abs/2406.10279). It studies package hallucinations in Python and JavaScript across sixteen models and 576,000 generated samples. The observed risk is erroneous or nonexistent package recommendations, with package-confusion and supply-chain consequences. Its rates belong to the tested models, prompts, and study period; they are not a current universal error rate.

The practical response is dependency-identity and lockfile review, not a new Elixir style matcher. Compilation can catch unresolved modules, but successful dependency resolution does not establish package trust. No dependency was added for the custom checks.

The inspected Perry abstract does not enumerate its languages, tasks, or vulnerability classes. Do not attach specific cryptography, injection, or authorization findings to that study without inspecting the full paper.

ExSlop provides practitioner hypotheses about recurring AI-associated idioms. It does not establish their prevalence. This pass found no measured basis for claiming that AI commonly duplicates Elixir code or routinely chooses any specific Enum idiom. Treat those claims as unproven.

Cross-language lessons that justify review, rather than attribution, are:

- Security-sensitive code needs independent validation even when it looks plausible.
- A fallback that hides a failure can produce a misleading success path.
- Repeated code can drift, but similarity alone does not justify a shared abstraction.
- Verbose comments or unfamiliar style are not evidence of a bug or AI authorship.

## Supplied methods report

`Code_Pattern_and_Anti_Pattern_Detection.md` explicitly states that its examples are illustrative and no detector was run. Accept its central distinction: structural rules specify a property; similarity retrieves candidates.

Its source leads include [Semgrep structural syntax](https://semgrep.dev/docs/writing-rules/pattern-syntax), [DECOR](https://doi.org/10.1109/TSE.2009.50), [DECKARD](https://doi.org/10.1109/ICSE.2007.30), and [SPINFER](https://www.usenix.org/conference/atc20/presentation/serrano). These support detection methods, not AI-error prevalence. This pass did not reproduce their experiments.

For this goal, use local AST checks with explicit boundaries. Defer clone engines, symbolic inference, and whole-program dataflow. Do not imply that a local matcher proves a runtime property across helper calls.

## Recommendations

Reuse existing Credo/ExSlop checks instead of copying their rescue, query, identity-map, or nesting checks. Add repository-specific checks only where source or correction history establishes a gap.

A **strong** check enforces an exact declared policy and fails CI. A **heuristic** points to an uncertain design decision and exits successfully. Each needs true positives, near-miss negatives, allowed exceptions, and source locations. No check should claim to identify AI authorship or auto-fix uncertain semantics.
