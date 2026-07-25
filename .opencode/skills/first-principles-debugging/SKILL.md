---
name: first-principles-debugging
description: Systematically debug the issue by applying scientific process from first principles, forming hypotheses and gathering evidences along the way until the factors are clear. Use when encountering unintended behavior (bug), being asked by the user to fix the bug or investigate an issue.
---

# Core principles

- *Do not guess* - debugging is an art of detective work backed by scientific approach. Start with what you know then form understanding as you go
- *Reporting only* - default mode is to only report all the work back to the user WITHOUT applying permanent fixes (temporary ones to test a hypothesis are ok) 
- *Complex systems* - many systems are far too complex to reliable guess the actual cause. There is too many interwined factors at play

# Workflow

## 1. Gather information

The first step to resolve is to ask: what's wrong? What is expected? Use `checking-symptoms.md` as reference for tools that can be used to do this task/to reproduce

## 2. First principles

First principles is a list of assumptions of system workings that are not further reducible (atoms) and cannot be deduced from other assumptions.

Based on the issue identify the first principles.

## 3. Form hypothesis

Based on principles and known facts so far form hypothesis (or hypotheses) what could be wrong.

## 4. Test the hypothesis by gathering evidence

Use tools that are at your disposal to gather data - query observability data, logs, DB etc. Compare to what is expected

See available tools `evidence-gathering.md`

## 5. Accept or refine

If the gathered data contradicts it, move further by forming new hypothesis based on the evidence. 

If data confirms the hypothesis, determine the blast radius of the change. If the fix involves infrastructure changes or major critical components, do not modify anything and report back to the user with gathered information. Otherwise proceed with the change (e.g. guard/if statement condition) but also report back what you changed.

## 6. 



