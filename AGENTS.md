# Documentation

# Keywords:

| Bold keyword(s)  | What to do  |
|---|---|
| **Always**  | follow instruction regardless of current circumstances  |
| **Always** with **when**, **only**, **unless** in the instruction | follow (or ignore) under described conditions. Requires judgement based on surrounding context  |
| **Never** | Absolutely forbidden under all conditions from doing the action. Must double check if the instruction was followed (pink elephant problem)  |
| **Never** with **unless** in the instruction | forbidden from doing the action but permitted under described conditions |

Hints:
 - **Never** vs **Always** with negation words: **Never** is much stronger and majority (~95%) of the time it's required to **not** do the described action.
 - Judgement based on surrounding context: instruction may state the reason. Use it to better understand the intent.
 - LLMs suffer from pink elephant problem, so all negative or forbidding instructions must be double checked.
 - user's instructions **always** override the instruction.

## Writing clarity

 - **Always** Adjust documentation prose and verbosity according to target audience (request by user or inferred from documentation structure) - beginner, technical audience with/without expertise etc. Do not under or overexplain just because it's convenient.
 - Prioritize (**unless** it's not relevant to the documentation) 
 - **Never** use parallel negativisms (e.g. "it's X, not Y", "This does not state Z" etc. One could call it legalese speak), **when** a constraint or limitation has been stated somewhere, relevant to the document. The negative statement can be inferred from the positive ones. 
 - **Always** use parallel negativisms or similar form **only** when they state an importnant limitation. The intent is to save crucial "why" decisions, not treat user like a dumb-dumb.
 - **Always** use `asd-ste100` (Simplified technical english) skill **when** writing technical explanation or communicating with the user  
 - **Never** use filler, fluff, exotic wordings **unless** they are part of the technical jargon, relevant to work being conveyed
 - **Always** use visualization  and examples to better plan, explain, elaborate etc. the concept. Use **when** relevant, do not overuse for every single question, doc section or answer: tables, pseudocode, code, worked examples, mermaid diagrams, comparisions, enumerations etc.
 - When documentation warrants example with code (source code, config etc.), **never** use concrete code fragments or values pasted directly from the codebase. They get oudated quickly and may confuse future readers. Use abstract enough but relevant to the context, values or code. Intent: minimize coupling between documentation and actual code.
 - **When** writing comments or explanation, do not explain in detail what the code does. Describe **briefly** what it does for reader. State "why"/rationale/limitations when relevant.


# Subagents

Use `scout` for:
- search codebase, docs, internet. 
- **Never** use it to design, explain or plan.

Use `worker` for:
- implementation. 

Use persistent (resume as needed) `worker` with `openai/gpt-6.1-terra`, thinking `xhigh` model for:
 - tasks that involve computer use/handling UI. Do not use it just because it's easier. Prioritize first programmatic access. When programmatic access becomes too difficult (failed after 2 attempts or no access at all), then use it.

- **Always** plan or design yourself.