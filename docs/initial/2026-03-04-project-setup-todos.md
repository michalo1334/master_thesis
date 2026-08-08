# Project Setup TODOs

Master checklist for setting up the thesis project infrastructure.

> **Superseded.** This is an early project-setup checklist. The canonical model — segment-to-segment policy with a deterministic in-memory operational projection — is defined in [Reachability Modeling — Canonical Policy, Transient Operational Flows](../plans/reachability-modeling.md). Historical record only.

## 1. Find & Secure Supervisor

- [ ] Draft outreach email/message with thesis topic summary (reference `docs/plans/2026-03-04-attack-graph-blast-radius-design.md`)
- [ ] Contact candidate supervisors
- [ ] Incorporate supervisor feedback on scope/direction into design doc
- [ ] Confirm supervisor agreement and any university paperwork

## 2. LaTeX Thesis Structure

- [ ] Add LaTeX template to `thesis/` directory
- [ ] Adapt template to chapter structure: Introduction, Related Work, Methodology, Implementation, Evaluation, Discussion, Conclusion
- [ ] Set up `latexmk` build tooling (Makefile or mix alias)
- [ ] Add `.gitignore` for LaTeX build artifacts (`*.aux`, `*.log`, `*.pdf`, etc.)
- [ ] Verify template compiles cleanly

## 3. Monorepo Structure

Target layout:

```
master-thesis/
├── thesis/              # LaTeX source
├── app/                 # Elixir/Phoenix application
├── docs/                # Design docs, plans, conventions
│   ├── plans/           # Design documents and research plans
│   ├── conventions/     # Coding conventions, architecture decisions
│   └── literature/      # Paper notes, bibliography, indexed sources
├── .github/             # CI, copilot instructions, skills
│   └── copilot-instructions.md
└── README.md            # Project overview and quickstart
```

- [ ] Create directory skeleton
- [ ] Write root `README.md` with project overview and quickstart
- [ ] Set up `.gitignore` (Elixir, LaTeX, Node, OS files)

## 4. Phoenix App Scaffold

- [ ] `mix phx.new` with LiveView + Postgres (no mailer)
- [ ] Add Mishka Chelekom UI dependency and configure
- [ ] Configure TypeScript for JS hooks (esbuild or standalone tsc)
- [ ] Verify `mix setup` works end-to-end
- [ ] Basic smoke test: app starts, root route renders

## 5. Database Setup

- [ ] Docker Compose for Postgres (dev environment)
- [ ] Initial Ecto migrations for graph model:
  - `hosts` (hostname, os, network_segment, criticality_score)
  - `services` (host_id, name, version, port)
  - `vulnerabilities` (service_id, cve_id, cvss_score, attack_complexity, privileges_required)
  - `edges` (source_service_id, target_service_id, edge_type, exploit_probability)
- [ ] Seed data: tiny hardcoded network for development (5 hosts, 3 segments)

## 6. Copilot Instructions

- [ ] Create/update root-level copilot instructions with project overview, conventions, build commands
- [ ] Add `app/lib/AGENTS.md` for Elixir/Phoenix conventions
- [ ] Add `thesis/AGENTS.md` for LaTeX conventions and chapter guidelines
- [ ] Document tech stack: Elixir, Phoenix LiveView, Postgres, Mishka Chelekom, TypeScript hooks

## 7. Conventions Document

- [ ] Elixir style: `.formatter.exs` config, credo rules (if using credo)
- [ ] Git workflow: branch naming (`feature/`, `thesis/`, `docs/`), commit message format
- [ ] Documentation conventions: where decisions go, how to reference literature
- [ ] Write to `docs/conventions/README.md`

## 8. Literature & Documentation Fetching

- [ ] Research available APIs: Semantic Scholar, arXiv, CrossRef, OpenAlex
- [ ] Build MCP server or mix task for querying academic sources
- [ ] Local storage structure for PDFs/notes in `docs/literature/`
- [ ] Index system: paper → topics/tags mapping (markdown or small DB)
- [ ] Integration goal: query "find papers on attack graph generation" from Copilot CLI → structured results
- [ ] BibTeX management: auto-generate `.bib` entries from fetched papers

## 9. Mix Tasks (Lightweight SDD)

- [ ] `mix precommit` — compile with `--warnings-as-errors` + format check + test
- [ ] `mix docs.check` — validate that plans/features have required sections (optional)
- [ ] Keep minimal — research project, not production app

## Priority Order

1. **Supervisor** — gates everything (they may change scope/direction)
2. **Monorepo structure** — foundation for all other work
3. **Phoenix app scaffold** — enables vertical slice development
4. **LaTeX setup** — can write introduction/related work early
5. **Copilot instructions + conventions** — improves all subsequent work
6. **Database + seed data** — needed for first vertical slice
7. **Literature fetching** — supports ongoing research
8. **Mix tasks** — quality of life, add as needed

## Tech Stack (Updated)

| Component | Technology |
|-----------|-----------|
| Backend | Elixir + Phoenix 1.8 |
| Frontend | Phoenix LiveView + Mishka Chelekom UI |
| JS Hooks | TypeScript (esbuild) |
| Database | PostgreSQL (via Docker) |
| Thesis | LaTeX (university template) |
| Stats | Python (scipy, matplotlib, Jupyter) |
| Literature | MCP server + local index |
| CI | GitHub Actions (mix precommit) |
