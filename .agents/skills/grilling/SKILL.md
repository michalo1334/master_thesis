---
name: grilling
description: Interview the user relentlessly about a plan or design. Use when the user wants to stress-test a plan before building, or uses any 'grill' trigger phrases.
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch
of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended
answer.

Ask the questions one at a time, waiting for feedback on each question before continuing. Asking multiple questions at
once is bewildering.

It's allowed to ask multiple questions via tool if each question is short. Longer questions or the ones that are not
trivial ask separately.

If a question can be answered by exploring the codebase, explore the codebase instead.

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
