# Evaluation study runtime contract — gate record

## Status

Implemented in the runtime-contract gate. This document records the condition
before the gate and the contract that the gate establishes.

The study lifecycle was unavailable to public callers before this gate. Later
slices added the Pilot and Final coordinators. F22+F23 then activated the public
lifecycle.

## Previous limitation

Before the gate, the study definition accepted scientific settings that the
optimization and simulation runtime could not execute. The collection path
carried these settings in a work item, but the runtime request omitted them and
used implementation defaults.

A valid study revision declared these settings:

- the defense action types that an optimization strategy could select;
- the pre-attack feasibility policy for plan selection;
- the objective for a simulation-backed strategy;
- the rule set for strategy scoring;
- the rule set for evidence simulation; and
- the pre-attack feasibility policy for evidence simulation.

A study could restrict one strategy to patch actions, and the optimizer could
still consider credential revocation and segment blocking. A study could select
a blast-radius objective and one attack rule, and the scoring runtime could
instead use its default combined objective and all default rules.

This difference changed the selected defense plan and the measured evidence. It
was a scientific contract failure, not only a provenance omission.

### Collection-boundary gaps

Topology segmentation was a valid declared strategy without a scoring block.
The old optimization contract expected nested simulation settings to supply its
initial foothold. A collection action could therefore build an incomplete
request and raise instead of returning a bounded study error.

A collection-item row stored a phase, replica position, and item position. The
old mapped action checked only the two positions. It did not rebuild the
canonical work from the stored immutable revision. A changed first request could
keep the same positions and change a graph, strategy, seed, root, count, or
other scientific value.

## Implemented contract

### Typed creation inputs

Optimization creation requires these explicit values:

- graph revision;
- strategy;
- budget;
- concrete selection seed;
- allowed defense action types;
- plan feasibility policy;
- initial foothold when the strategy reads one; and
- scoring settings when the strategy scores candidates.

Scoring settings hold the declared objective, rule set, trial count, iteration
count, and maximum attempts. The request names the foothold once at its top
level. A scoring block on a strategy that does not score candidates is a
validation error.

Evidence simulation creation requires the declared graph revision, foothold,
concrete or generated root seed, attack count, iteration count, maximum
attempts, rule set, and feasibility policy.

The study path fills no omitted scientific value with a runtime default.

### Allowlisted name resolution

`NetworkDefense.DefenseActions.Registry` resolves defense action names.
`NetworkDefense.Simulation.RuleSet` resolves simulation rule names through a
fixed map. An unknown name returns a bounded validation error before
persistence or computation. No code converts an arbitrary string into an atom
or a module.

### Runtime application

The optimizer receives the resolved action modules and the feasibility policy
of the stored run. It selects no action outside the declared set, and a disabled
policy skips only the pre-attack rejection.

A simulation-backed strategy uses the persisted scoring objective and rules.
Evidence simulation uses the persisted evidence rules and feasibility policy,
and it never calls the default-rule helper for prepared work.

### Persisted effective settings

An optimization run stores the allowed action names, the feasibility policy,
the initial foothold, and the full scoring configuration in its execution
configuration. An experiment stores its rule names and feasibility policy.

Execution and retry accept a stored identifier plus operational options only.
Both load the persisted settings, so a caller cannot supply replacement
scientific values.

Creation validates the canonical request before the first link. A study
reservation retry returns the linked runtime record unchanged, because the
mapped action rebuilds the canonical request from the immutable revision.

### Canonical work verification

The mapped action now:

1. loads the collection item and its phase;
2. accepts only a supported collection role;
3. loads the execution and the immutable study revision;
4. parses the stored normalized definition;
5. rebuilds the work for the item replica;
6. selects the canonical item by item position;
7. builds complete runtime creation requests from that item; and
8. creates and links missing runtime records in short transactions.

Final-phase items became supported when the later Final source-binding and collection slices were completed.

## Compatibility

Existing dashboard requests keep their behavior. The dashboard resolves its
selected choices into explicit typed values before runtime execution. Its random
seed switch stays local to the dashboard: the LiveView replaces the submitted
seed with one concrete seed before typed parsing, so no generate flag enters the
contract or persistence.

A migration backfills existing optimization and simulation records with the
effective defaults that produced them. It rejects legacy rows whose required
configuration is missing or incomplete.

The gate adds no generic policy engine, dynamic module loading, or second
workflow framework.

## Verification

Focused automated checks cover these behaviors:

1. A restricted defense-action list cannot produce another action type.
2. A non-default scoring objective and rule subset reach the strategy.
3. Evidence simulation uses its persisted rule subset.
4. Topology segmentation returns a typed result or bounded error and does not
   raise.
5. An item from an unsupported phase creates no runtime record.
6. A retry returns the linked runtime record and starts no second one.

## Completion state

The Pilot coordinator, Final path, and public lifecycle now satisfy this gate.
The lifecycle accepts collection evidence only through those coordinator
boundaries.
