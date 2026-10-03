# Established Elixir patterns

Research used a parallel explorer agent with the explicit `openai-codex/gpt-6-luna` model. The main agent compiled this report. Sources below were fetched from moving branches, not pinned releases. They establish design examples, not universal rules or measured detector accuracy.

## Sources and observations

| Project | Inspected source | Useful pattern | Limit |
| --- | --- | --- | --- |
| Phoenix | [README](https://raw.githubusercontent.com/phoenixframework/phoenix/main/README.md), [router](https://raw.githubusercontent.com/phoenixframework/phoenix/main/lib/phoenix/router.ex) | Ordered, scoped request pipelines keep request concerns at the web boundary. Domain operations can sit behind context interfaces. | Router inspection does not prove that every application needs the same context structure. |
| Ecto | [README](https://raw.githubusercontent.com/elixir-ecto/ecto/master/README.md) | Separate data mapping, changesets, and persistence. Translate validation and persistence failures deliberately. | Full changeset and constraint guides were not inspected in this pass. Treat detailed recommendations as design guidance, not findings from the README alone. |
| Oban | [README](https://raw.githubusercontent.com/oban-bg/oban/main/README.md), [source](https://raw.githubusercontent.com/oban-bg/oban/main/lib/oban.ex) | Durable jobs use database persistence; `Ecto.Multi` composition can make a data change and job insertion atomic. | Not every job must be in the same transaction as its caller. Independent jobs are legitimate. |
| Broadway | [README](https://raw.githubusercontent.com/dashbitco/broadway/main/README.md) | Back-pressure, acknowledgement, batching, failure handling, and graceful shutdown are explicit streaming concerns. | A stream processor and a durable discrete-job queue solve different problems. |
| Plug | [README](https://raw.githubusercontent.com/elixir-plug/plug/main/README.md) | Compose HTTP behavior through a connection pipeline rather than repeat controls in each action. | Pipeline membership alone does not prove authentication or authorization. Public routes need exceptions. |
| Credo | [README](https://raw.githubusercontent.com/rrrene/credo/master/README.md) | Static analysis can teach conventions through focused checks and useful explanations. | A lint finding does not establish a defect or AI authorship. |

## Source and guide follow-up

The follow-up inspection on 2026-10-03 covered code-pattern guidance beyond READMEs:

- [Ecto 3.14.2 changesets](https://hexdocs.pm/ecto/Ecto.Changeset.html#module-validations-and-constraints) distinguishes pre-database validations from database-backed constraints. Its example composes casting, validation, and `unique_constraint/3`. Declared constraints translate expected database failures into changeset errors; this is not a reason to rescue every persistence failure.
- [Phoenix 1.8.15 contexts](https://hexdocs.pm/phoenix/contexts.html) describes ordinary Elixir modules that encapsulate data access and validation. The web layer exposes a larger application. Contexts can group related resources; the guide does not require one context per resource.
- [Plug 1.20.3 CSRF protection](https://hexdocs.pm/plug/Plug.CSRFProtection.html) shows session setup and fetching before CSRF protection. URL-scoped tokens bind a host, with explicit configured exceptions. This supports checking ordering and deployment assumptions, not merely the presence of a plug name.
- [Oban worker tests](https://raw.githubusercontent.com/oban-bg/oban/main/test/oban/worker_test.exs) use test-local worker modules, `@impl Worker`, and an async test case. The inspected excerpt establishes those idioms, not a retry or transaction guarantee.

These documentation versions may differ from the application's lockfile. Check the installed version before applying API-specific advice.

## Implications for this repository

- **Errors:** keep domain failures explicit. Translate them at boundaries instead of erasing their cause. Broad rescue is a review signal, not automatically wrong.
- **Security:** centralize request controls, but verify actual routes and data handling. Do not infer sensitivity from a route name.
- **Contexts:** keep domain decisions out of transport adapters. A source-level rule needs a declared forbidden dependency; it cannot discover the right architecture.
- **Async work:** distinguish durable orchestration from transient distributed computation. Test acknowledgement, duplicate delivery, failure, and transaction behavior.
- **Structure:** preserve ownership boundaries. Extract repeated behavior only when semantics match, not merely because syntax looks similar.
- **Tests:** test observable outcomes and failure cases. A test file's existence proves neither coverage nor TDD.

The source already has an error-code/type consistency check. Reimplementing it adds no value. Generic rescue, Enum, and query-in-loop checks also overlap with ExSlop. New checks should target demonstrated local gaps.

## README structure

Phoenix leads with project identity. Broadway states its purpose before its features. Oban separates features, requirements, installation, quick start, and further reading.

Adapt that order: purpose and scope → three real product screenshots → tested local start → roadmap → specialist documentation. Do not copy badges, contribution boilerplate, or a library-sized feature catalogue. Keep the existing documentation links, but let readers see what the application does first.
