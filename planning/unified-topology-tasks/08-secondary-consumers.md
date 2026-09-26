# Chunk 08: Secondary Consumers

## Objective

Migrate mission-flow editing and simulation reports away from the old projection API and renderer.

## Dependency

Chunk 07 must pass.

## Mission required flows

Update `RequiredFlowsField.svelte` and its parent inspector path.

- Read accepted `TopologyProjection.flow_groups` from the active editable document.
- Derive each source segment from the projected source host membership.
- Derive target choices from each group's `service_ids`.
- Keep draft-reachability labeling.
- Do not fetch a saved-revision projection.

## Simulation reports

- Add `topology_projection` to `fetch_simulation_report_reply.ex`.
- Build it from the same report graph in `dashboard_live.ex`.
- Remove the reply's old `operational_flows` field after frontend migration.
- Regenerate TypeScript contracts.
- Store the projection in `SimulationReportDocument.svelte.ts`.
- Replace the Topology/Network toggle in `HeatmapCanvas.svelte` with the unified read-only canvas.
- Drive policy and flow heat appearance from grouped projection edge and flow IDs.
- Update required-flow availability checks to use projected host membership and service IDs.
- Update report tests and contract tests.

## Acceptance

- No mission inspector calls `fetchGraphProjection`.
- Simulation reports do not import `NetworkCanvas` or `projectNetwork`.
- Reports retain host, policy, and flow heat appearance.
- Report required-flow availability remains correct.
- Generated contracts contain the new report projection field and no report dependency on the old operational-flow contract.

## Focused checks

Run simulation-report, heatmap, inspector, contract, and LiveView tests. Run contract generation checks, Svelte checks, and formatting.
