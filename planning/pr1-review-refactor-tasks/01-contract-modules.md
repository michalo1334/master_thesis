# Chunk 01: Projection Contract Modules

## Objective

Address the Elixir part of comments `4111204706` and `4111209798`.

## Scope

- Rename child contracts to `TopologyProjection.*` modules.
- Move each child module into a matching `topology_projection/` file.
- Update root aliases and embeds with fully qualified module names.
- Add registry-backed conversion for short node and canonical relationship atoms.
- Replace projection-local type conversion clauses.
- Update Elixir contract registry expectations.

## Constraints

- Keep all schema fields and wire values unchanged.
- Keep ID arrays as references.
- Keep `Attachment.anchors` as an owned embed.
- Do not hand-edit generated TypeScript.
- This chunk can leave frontend imports pending for chunk 02. Backend checks must pass.

## Acceptance

- Child modules use the `TopologyProjection.*` namespace.
- Known short atoms resolve through node and relationship registries.
- Unknown tags have a defined, tested result.
- Projection-specific conversion clauses are gone.

## Checks

Run focused registry, contract, projector, and dashboard contract tests. Run Elixir formatting and compilation.
