# Evaluation study runtime contract — future work

## Status

This work is deferred. This document records a known prototype limitation. It does not authorize implementation.

The study definition accepts scientific settings that the optimization and simulation runtime cannot execute yet. The current collection path can carry these settings in a work item, but the runtime request can omit them and use implementation defaults.

Until this work is complete:

- keep the study lifecycle unavailable to public callers;
- do not treat collection output as conformant study evidence when a declared setting can differ from the runtime default;
- do not use the collection path for a real evaluation result; and
- do not claim that immutable study revisions fully control optimization or simulation execution.

## Current limitation

A valid study revision can declare these settings:

- the defense action types that an optimization strategy can select;
- the pre-attack feasibility policy for plan selection;
- the objective for a simulation-backed strategy;
- the rule set for strategy scoring;
- the rule set for evidence simulation; and
- the pre-attack feasibility policy for evidence simulation.

The current runtime contracts do not carry all these values. The domain runtime can replace omitted values with its built-in defaults.

For example, a study can restrict one strategy to patch actions. The current optimizer can still consider credential revocation and segment blocking. A study can also select a blast-radius objective and one attack rule. The current scoring runtime can instead use its default combined objective and all default rules.

This difference can change the selected defense plan and the measured evidence. It is a scientific contract failure, not only a provenance omission.

## Additional collection-boundary gaps

### Topology segmentation

Topology segmentation is a valid declared strategy without a scoring block. The current optimization contract still expects nested simulation settings to supply its initial foothold. A collection action can therefore construct an incomplete request and raise instead of returning a bounded study error.

### Canonical work binding

A collection-item row stores a phase, replica position, and item position. The current mapped action checks only the two positions. It does not rebuild the canonical work from the stored immutable revision.

A changed first request can therefore keep the same positions but change a graph, strategy, seed, root, count, or other scientific value. Reservation identity protects an existing link, but it does not protect the first reservation.

## Required future behavior

### Complete typed runtime inputs

Optimization execution must receive these explicit values:

- graph revision;
- strategy;
- budget;
- concrete selection seed;
- allowed defense action types;
- plan feasibility policy; and
- scoring settings when the strategy uses simulation.

Scoring settings must include the declared objective, rule set, trial count, iteration count, maximum attempts, and initial foothold.

Evidence simulation must receive the declared graph revision, foothold, concrete root seed, attack count, iteration count, maximum attempts, rule set, and feasibility policy.

The study path must not fill an omitted scientific value with a runtime default.

### Allowlisted name resolution

Convert defense-action and simulation-rule names through fixed allowlists. Do not convert arbitrary input strings into atoms or modules.

An unknown name must return a bounded validation error before persistence or computation.

### Runtime application

The optimizer must use only the declared defense action types. It must apply the declared feasibility policy when it evaluates and applies a defense.

A simulation-backed strategy must use the declared scoring objective and scoring rules.

Evidence simulation must use the declared evidence rules and evidence feasibility policy. It must not call the default-rule helper for study work.

### Persisted identity

Persist the effective scientific configuration with each optimization run and experiment.

Optimization identity must include:

- graph revision;
- strategy;
- budget;
- concrete seed;
- defense action types;
- feasibility policy; and
- complete scoring configuration.

Experiment identity must include:

- graph revision;
- trial and iteration counts;
- maximum attempts;
- initial foothold;
- concrete seed;
- rule set; and
- feasibility policy.

A retry with different scientific settings must return a bounded mismatch error. It must not replace the existing linked record.

### Canonical work verification

Before the first reservation, the mapped action must:

1. Load the collection item and its phase.
2. Confirm that the phase has a supported collection role.
3. Load the execution and immutable study revision.
4. Parse the stored normalized definition.
5. Rebuild work for the item replica.
6. Select the canonical item by item position.
7. Compare the complete canonical item with the supplied work item.
8. Start reservation only when the values are equal.

A Final-phase item must remain unsupported until the Final source binding exists.

## Compatibility

Existing dashboard requests can preserve their current behavior. They must resolve their current choices into explicit typed values before runtime execution, as the dashboard already does for generated seeds.

A migration must backfill existing optimization and simulation records with the effective defaults that produced those records. This keeps old identity checks stable.

The change must not add a generic policy engine, dynamic module loading, or a second workflow framework.

## Verification

Use focused automated checks for these behaviors:

1. A restricted defense-action list cannot produce another action type.
2. A non-default scoring objective and rule subset reach the strategy.
3. Evidence simulation uses its persisted rule subset.
4. A changed feasibility policy causes an identity mismatch.
5. Topology segmentation returns a typed result or bounded error and does not raise.
6. A same-position work item with a changed scientific field creates no runtime record.
7. An item from an unsupported phase creates no runtime record.

Use a small fixture-backed mismatch table for identity fields. Do not create an exhaustive combination matrix.

## Completion gate

Complete this work before the real Pilot coordinator or public study lifecycle can accept collection evidence. The lifecycle must not produce a scientific result while this limitation remains.
