# Shared instructions

## Documentation

## ASD-STE100 & writing clarity

**Always** use `asd-ste100` skill when writing documentation or outputting an explanation, text or anything else that is
directed towards communication with the user.

**Always** use plain and concise English language, do not use filler or less common, exotic wordings unless they
represent exact technical jargon and there is no alternative way to describe a definition, concept etc.

When being prompted to review documentation for clarity towards the intended audience, follow
`writing-clearly-and-concisely` skill as suplemental.

## Decoupling the intent and implementation

When documentation warrants code or pseudo code, do not use concrete code fragments or values pasted directly into the
documentation. It gets outdated quickly. Instead refer to concrete modules, files or use illustrative code or values
(abstract enough it doesn't get confused with real one).

In short: document in a way that minimizes coupling between the implementation and description. Ask yourself a question:
When source code or file contents change, how much documentation must change because of appearance rather than
functionality?

## Example based

For complex documentation use examples, either enumerating inline (`e.g. ...`) or full worked ones that led the reader
step by step to better turn abstract description into concrete chain of action.

## Illustrating

Use _visualization_ to let reader better understand the intent behind the words. One clear diagram explains more than
detailed paragraphs in English. _Visualization_ is not just embedded monolithic blocks that break wall of text but also
inline code (or pseudocode) examples, mathematical expressions. Think rich text like in MS Word.

**Do not** add visualization just in case for every single paragraph. It introduces unnecessary noise for the reader.

Judge the relevant section and rate whether it warrants a visualization aspect or plain paragraph of text is sufficient.

Examples of visualizing:

- code & pseudocode examples - snippets, example config values, class names, public interface (API, OOP etc.) names
- tables
- images
- input and output examples - interface usage with parameters, example output
- mermaid diagrams - C4, state machine, sequential, activity, flowchart
- LaTeX - for mathematical formalisms

## Relevancy

Phrases such as `complex` or `every single` were left vague intentionally as it's difficult to exactly quantize when one
should add visualization or example. Rate the difficulty indvidually. Consider each time perspective of: 1. domain
expert, 2. first time reader, engineer or user that wants to better understand the context. 3. a person with basic
domain knowledge. How much each group can construct of their own internal understanding?

**Important**: do not dumb down documentation just because it needs to be accessible for everyone. Each documentation
can and should be addressed to different groups.

# Workflow

- Use the `scout` agent for codebase exploration when subagent tools are available.
- Use the `worker` agent for implementation when subagent tools are available.
- If delegation is unavailable, report the limitation and continue directly with the same verification requirements.
- Do not assume that a named tool, skill, or agent exists. Check the available capabilities first.
