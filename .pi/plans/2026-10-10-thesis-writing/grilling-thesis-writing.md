# Thesis-writing decision tree

**Status:** In progress  
**Project repository:** `/home/michalo/master_thesis` at `d94ba40`  
**Manuscript repository:** `/home/michalo/thesis` at `55a7cec`

Thesis writing
├─ Delivery constraints
│  ├─ Deadline: 30 Sep 2027 [#](#deadline)
│  ├─ Weekly capacity: 10 protected hours [#](#weekly-capacity)
│  ├─ Review cadence: unanswered
│  └─ Institution rules: unanswered
├─ Thesis contract
│  ├─ Language: unanswered
│  ├─ Research question: unanswered
│  ├─ Contribution: unanswered
│  └─ Claim limits: partly known from repositories
├─ Evidence strategy
│  ├─ Azure feasibility: unanswered
│  ├─ Evidence cutoff: unanswered
│  ├─ Fallback thesis: unanswered
│  └─ Provenance gates: defined in foundation documents
├─ Manuscript design
│  ├─ Chapter structure: draft exists
│  ├─ Literature method: unanswered
│  ├─ Claim matrix: not created
│  └─ Front matter: placeholders exist
└─ Execution plan
   ├─ Milestones: blocked by deadline
   ├─ Writing order: blocked by thesis contract
   ├─ Evaluation work: blocked by evidence strategy
   └─ Final review: blocked by delivery constraints

# Repository findings

The implementation repository contains an Elixir/Phoenix simulator with a Svelte interface. It models network context, stochastic attack trajectories, and defense selection. The repository does not describe a penetration-testing product.

The manuscript repository contains a populated LaTeX draft. Its chapter structure is usable, but the title, summaries, keywords, literature method, and some chapter content still need work.

The current evidence supports the simulator design and local workflow validation. It does not support final claims about defense performance. The planned Azure study and its required tooling are incomplete.

The thesis plan must separate three claim types:

1. Implementation claims need code or project-document evidence.
2. Empirical claims need accepted evaluation archives and analysis.
3. External claims need publications.

# Delivery constraints

## Deadline

### Question

What is the official submission deadline?

Please also state any earlier fixed date when your supervisor or institution must receive a complete draft.

### Recommendation

Set an internal completion date at least 14 calendar days before the official deadline. Use that interval only for supervisor changes, citation checks, formatting, compilation, and submission problems.

### Answer

The official submission deadline is **30 September 2027**.

The recommended internal completion date is **16 September 2027**. This leaves 14 calendar days for supervisor changes, citation checks, formatting, compilation, and submission problems.

The user accepted the recommended correction from the invalid date `31.09.2027` to `30.09.2027`.

## Weekly capacity

### Question

How many protected hours can the user reliably spend on the thesis each week?

The estimate includes writing, evaluation work, reading, and supervisor revisions. It excludes time that is only occasionally available.

### Recommendation

Use **10 protected hours per week** as the planning baseline. This capacity supports two focused work blocks and one longer weekly session.

### Answer

The user selected **10 protected hours per week**.

The plan must not use occasional free time as required capacity. Milestones must fit within the 10-hour baseline.
