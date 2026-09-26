# Chunk 02: Projection Contract Consumers

## Objective

Complete comments `4111204706`, `4111210455`, `4111211558`, `4111211972`, and `4111212366`.

## Scope

- Run `mix gen.contracts` after chunk 01.
- Confirm child aliases move to the topology-projection barrel and use leaf names.
- Update imports in the topology scene adapter, placement helper, test fixtures, layout tests, and contract tests.
- Delete obsolete generated aliases through the generator output.
- Add concise test documentation that ID arrays are sorted normalized references.
- Include generated files in the final change.

## Constraints

- Do not change JSON fields, nullability, enum values, or ordering.
- Do not use `embeds_many` for host, service, edge, flow, or heterogeneous issue references.
- Do not hand-edit generated files.

## Acceptance

- Generated contracts have no stale `TopologyProjectionHost`-style aliases.
- All non-generated imports use the new namespace.
- Projection fixtures and wire assertions remain structurally unchanged.
- The reason for ID arrays is recorded in focused tests or type documentation.

## Checks

Run contract generation twice and confirm stable output. Run affected frontend tests, frontend typecheck, contract tests, and LiveView projection tests.
