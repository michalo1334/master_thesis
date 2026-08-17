# Mission Feasibility Optimization

## Goal

Select defenses that keep declared capabilities operational before an attack.
Then minimize modeled mission impact. Use blast radius as the next ranking value.

## Model

A mission capability declares required service flows. Each flow identifies a source segment and a target service.

A capability is operational when all required flows exist, the target service hosts are not compromised, and enough supporting hosts remain uncompromised.

The optimizer rejects a defense plan that makes a required capability unavailable before the attack.

The optimizer ranks valid plans in this order:

1. Expected mission impact.
2. Expected blast radius.
3. Defense cost.

## Implementation

1. Add required-flow data to mission-capability contracts and node data.
2. Extend mission-impact calculation with flow and service-host status.
3. Use the same calculation to check pre-attack feasibility.
4. Score simulation-backed candidates with mission impact and blast radius from one experiment.
5. Filter invalid candidates for every strategy.
6. Add mission capabilities and required flows to the generated evaluation scenario.
7. Show capability status and baseline-versus-defended results in the dashboard.
8. Add backend, frontend, and characterization tests.

## Destructive Changes

The old selectable optimization objective is obsolete. Remove it from backend contracts, persistence, reports, telemetry, and dashboard state.

Drop the `optimization_runs.objective` column. Do not preserve compatibility for old objective values.

## Evaluation

Compare blast-radius-only, mission-impact-only, and mission-first/blast-radius-second ranking. Run each model with and without the feasibility constraint. Use paired scenario and evaluation seeds.

The thesis contribution is a controlled simulation comparison. It is not a claim that multi-objective hardening or mission-impact assessment is new.

## Literature

Use multi-objective hardening work by Dewri et al. (2007) and Enoch et al. (2022). Use mission-impact work by Holsopple et al. (2015) and Musman and Temin (2015).
