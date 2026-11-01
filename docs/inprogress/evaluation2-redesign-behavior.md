# Evaluation2 redesign — reuse, behavior, and documentation

> Design-interview history. Later decisions can supersede earlier proposals and example interfaces.
> Use the [native operator guide](../evaluation2.md), [current architecture](../architecture/evaluation-architecture.md) and [stable verification record](../history/evaluation2-verification.md) for implemented behavior and status.

> Part of the [Evaluation2 redesign index](grilling-evaluation-redesign.md).

## Reuse

### Reuse boundary

**Question:** Which old code should survive?

**Proposed answer:** Retain the established algorithms and domain operations. Extract useful transformations from their lifecycle wrappers.

| Reuse | Simplify around it |
| --- | --- |
| YAML parser, schema, and scientific definition checks | Repeated full validation on stored-definition loads |
| Graph, optimization, and simulation APIs | Phase-specific request wrappers and repeated canonical-work reconstruction |
| Sampling, seed derivation, bootstrap, and Holm calculations | Study metadata carried through pure numerical operations |
| Matrix assembly and required replica comparison | Duplicate evidence/history checks at later stages |
| Stable domain effect links | Phase/run/receipt representations that only mirror workflow progress |

Use the proposed module and evidence shapes above as the current working model.

## Behavior cases

### Q10 — Check policy

No automated-test design for now. Keep behavior cases as implementation requirements.

#### Construction rule

```text
IF the application fully controls how a fact is created,
THEN construct the fact correctly and do not check it again later.

IF a fact depends on observed evidence, an external boundary, resource use,
or concurrent lifecycle state,
THEN keep one check or calculation at the owning boundary.
```

```text
Constructed facts
  declared comparison order
  shared attack-column identity
  planned matrix dimensions
  mapped item identity

Necessary checks or calculations
  YAML and compute boundary decoding
  candidate fits available Pilot evidence
  Pilot informativeness and precision
  Final environment stability
  Final replica equality
  valid resume selection
  lifecycle state during acceptance
  resource limits at use
```

```text
EVAL-INPUT-01
WHEN study YAML fails the creation contract,
THE application SHALL reject it before collection.

EVAL-APPROVAL-01
WHEN approval selects an invalid candidate,
THE study SHALL remain waiting.

EVAL-RETRY-01
WHEN collection retries the same work item,
THE collection SHALL reuse its domain effect links.

EVAL-PILOT-01
WHEN a Pilot candidate exceeds the available evidence,
THE Pilot SHALL reject that candidate as ineligible.

EVAL-PILOT-02
WHEN any outer subsample is non-informative,
THE candidate/comparison assessment SHALL be non-passing.

EVAL-PILOT-03
WHEN no candidate passes every declared comparison,
THE Pilot SHALL return :insufficient.

EVAL-EVIDENCE-01
WHEN evidence is assembled,
THE builder SHALL use the declared family order and one shared attack-column list for both sides.

EVAL-FINAL-01
WHEN measured Final replicas disagree,
THE application SHALL reject Final evidence.
```

Automation of these cases is deferred.

## Documentation follow-up

**Open:** Review whether the evaluation documentation needs one shared glossary after the module and contract names stabilize.

The glossary could distinguish these terms:

```text
tier                 one of the small, medium, or large network sizes
Pilot candidate       a proposed pair of plan and attack sample counts
seed                  a deterministic random-stream input with a declared role
matrix                plain aligned plan-row and attack-column observations
comparison family     the complete set corrected together
```

Also search existing documentation for older or ambiguous uses of `tier`, `network size`, `scenario`, `candidate`, and `seed`. Update them only after the redesign fixes the final names.
