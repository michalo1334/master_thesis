---
name: grilling
description: Interview the user relentlessly about a plan, design, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map the decisions as a **design tree**, with
branches for dependent decisions.

The **frontier** contains only open decisions whose prerequisites are settled. Ask questions from this frontier, then
wait for the user's answers. Recompute the frontier after each response. Defer questions that depend on an unanswered
question to a later round.

Ask one question at a time by default. You may group short, independent questions in one tool call. Ask long or complex
questions separately. Number each question and provide a recommended answer. Word it so "yes" accepts that
recommendation. Record recommendations as decisions only after the user accepts them.

Find facts in the codebase or environment yourself instead of asking the user to look them up. When delegation is
available, send fact-finding to a subagent. A pending exploration is an unsettled prerequisite: defer dependent
questions, but continue with independent ones. If delegation is unavailable, inspect the relevant sources directly.

Finish only when every branch is resolved and no questions or explorations remain pending. An empty frontier with
unsettled prerequisites is not completion. Ask the user to confirm the shared understanding before acting on the plan.

Keep the questions and answers in grilling-<title>.md.

The format is a recursive tree, with each branch representing a category or sub-category and each leaf a brief (one or
two, max four word) question and short answer provided from me or as result of exploration; the next section is a full
Q&A with necessary details requested by me.

Provide initial categories and subcategories in a tree, refined as we go.

Nesting level of categories must not exceeded depth of three. Treat as hint of complexity.

```
<title>
├─ category1
├─ category2
│  ├─ subcategory1
│  │  ├─ question11: decision answer [#](#link_to_section)
│  ├─ question1: decision answer
│  ├─ question2: decision answer
│  ├─ ...
...

# Category 1

detailed answer (if provided) and rejected alternatives

## Subcategory1

### Question11

detailed answer (if provided) and rejected alternatives

...
```
