# Chunk 12: Connection Detail Refinement

## Objective

Keep one segment-pair connection line at every zoom level. Show host-level direction in connection details.

## Dependency

Chunk 11 must pass.

## Connection line

Render one directed bundle per ordered segment pair at far, medium, and near zoom. Do not restore separate policy or operational-flow lines at higher zoom levels. Keep self-segment policy as a header indicator without a loop line.

The bundle count remains the number of unique policy edge IDs plus unique operational flow IDs.

## Bundle details

Replace service-only rows such as `SSH` with directional rows such as:

`SSH · host-a → host-b`

Build each row from an accepted projection flow group:

- service label;
- source host label;
- target host label.

Sort rows by service label, source host label, target host label, and stable IDs. Deduplicate identical rows. Keep `No services` for policy-only bundles.

The accessible bundle name includes its segment direction, connection count, and directional connection summary.

## Host selection

When the user selects a host, show a view-only list of that host's outgoing projected connections. Use the same directional rows as the bundle popover. Include connections across all target segments. If the host has none, show `No outgoing connections`.

The host connection list:

- opens when host selection changes to that host;
- stays associated with the selected host;
- closes when selection changes, selection clears, or Escape is pressed;
- does not add lines, change graph data, or change projection state.

## Boundaries

- Use accepted projection flow groups for source host, target host, and services.
- Use graph nodes only for display labels.
- Do not infer membership or flow semantics from raw edges.
- Keep one segment-pair line at every zoom level.
- Keep `Contains` relationships hidden.
- Do not change the server projection contract.

## Acceptance

- Far, medium, and near zoom show bundle lines and no detailed policy or flow lines.
- Bundle hover, focus, and click details show `service · source host → target host` rows.
- Selecting a host shows only that host's outgoing connections.
- Incoming-only connections do not appear in that host list.
- Directional rows are deterministic and deduplicated.
- Policy-only bundles show `No services`.
- Escape and selection changes close the correct detail surface.
- Heatmap bundle appearance remains correct at every zoom level.

## Focused checks

Run bundle-builder, unified-canvas, semantic-zoom, heatmap, selection, inspector, and editable-canvas tests. Run the full frontend suite, Svelte checks, accessibility checks, formatting, and style lint.
