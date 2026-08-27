# Documentation Cleanup Execution

## Design

The canonical set describes current behavior for thesis reviewers and maintainers. Code and tests establish behavior. The thesis contains the full research narrative. Repository docs state the scope, model, operation, and reproduction path without retaining historical working material.

The model uses four focused pages. A shared synthetic micro-scenario gives readers concrete examples across graph, attack, defense, and evaluation behavior. Each page links only to the implementation locations that establish its behavior.

## Execution

1. Create the conceptual foundation.
   - Create scope and EARS requirements pages in `docs/concepts/`.
   - Retain and reduce the glossary to shared model terms.
   - State the approved research framing, the three-tier scale-study design, and the current baseline-only gap.

2. Split the model documentation.
   - Replace `model.md` with graph, attack, defense, and evaluation lifecycle pages.
   - Merge fixed-topology and scenario provenance into scope and graph pages.

3. Update operational and delivery documentation.
   - Update README, architecture, and infrastructure for the retained boundary.
   - Move Azure and CI/CD plans to `docs/inprogress/`.
   - Add the concise topology-scale study protocol to `docs/inprogress/`.
   - Keep statistical analysis details in `evaluation/analysis/README.md`.

4. Document dashboard design.
   - Create `docs/design/dashboard.md` with the approved workflows, stable-input rationale, user-flow diagram, and core-journey GIF.

5. Delete historical material and reconcile links.
   - Remove superseded drafts, completed plans, comparisons, wireframes, checklists, ADR stub, scratch files, scenario-local rationale, and generated LaTeX output.
   - Repair links that targeted removed or moved documents.
   - Confirm that every retained Markdown link resolves and each model claim has a source reference.

## Verification

- When a retained Markdown document links to another local document, the target shall exist.
- When a model page states current behavior, the cited implementation shall support that statement.
