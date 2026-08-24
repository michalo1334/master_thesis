# Statistical Analysis Report UI Follow-up

## Problem

The final-analysis metadata renders `input_hashes`, `analysis_configuration`,
and `dependencies` as compact JSON inside summary grid cells. Long hashes and
JSON tokens have no safe breakpoints, so they overflow their cards and overlap
adjacent content.

The same summary uses hand-written `<dl>` card markup and local card styles.
The simulation and optimization reports already share `KpiCards.svelte`, so
the statistical report now has a third, inconsistent card implementation.

## Scope

Use `KpiCards.svelte` for concise scalar metadata such as mode, model, trial
count, runtime, uncertainty, schema version, package version, and pilot status.
Move hashes, configuration, dependencies, and the estimand into a separate
reproducibility section designed for structured or long-form values.

Do not place raw JSON in KPI cards. Present structured values as readable
key-value rows or a contained code block. Long identifiers and hashes must use
safe wrapping or local horizontal scrolling without widening the report.

## Acceptance Criteria

- The statistical report reuses the shared KPI card component.
- Structured metadata remains readable and does not overlap adjacent content.
- The report has no page-level horizontal overflow at desktop or mobile widths.
- Input hashes, configuration, dependencies, and the estimand remain available.
- Component tests cover a long hash and a multi-entry metadata object.
