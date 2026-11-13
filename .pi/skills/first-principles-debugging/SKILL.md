---
name: first-principles-debugging
description: Systematically debug the issue by applying scientific process from first principles, forming hypotheses and gathering evidences along the way until the factors are clear. Use when encountering unintended behavior, being asked by the user to fix the bug or investigate an issue.
---

# Core principles

- _Do not guess_ - debugging is an art of detective work backed by scientific approach. Start with what you know then
  form understanding as you go
- _Complex systems_ - many systems are far too complex to reliable guess the actual cause. There is too many interwined
  factors at play.
- _Occam's Razor_ - start with the most simplest, direct and obvious hypotheses before diving deeper
- _Multi level_ - not all causes lie in the code right before your "eyes", some of them are at machine, external
  integration or even organizationial level.
- _Hypothesis is not a mathematical proof_ - hypothesis is a statement that is backed by observations that weaken or
  strengthen it, never prove its correctness.

# Glossary

| Term | Explanation | Notes | | ----------- | ----------- | | Hypothesis | Falsifable explanation of observed behavior
| | Prediction | Expected result of the experiment | | Observation | Measured actual outcome of experiment | | Fact |
Derived truthful statement from observations about the system behavior or its components. |

# Boundaries

## Investigation only

The investigation lifecycle is to **only** discover causes, not apply fixes to them. It's allowed to make temporary
changes in the source code, add testing etc. to solely understand the behavior and reproduce the issue under different
conditions. User decides whether to expand the scope with applying the fix (if any).

## Occam's razor

Given set of facts and tested hypotheses so far, establish the **most** obvious, **most** simplest, most direct one that
one could come up with. Do **not** start with hypothesis that claims the problem lies in architecture or in
infrastructure unless you cleared out the "ground" ones.

Hypothesis-driven debugging is a marathon, not a sprint. Slow is smooth and smooth is fast.

## Stopping early

A confirmed simple prediction with approved fix can finish the ticket, but does it addresses the underlying problem? The
actual root causes can sit much higher up e.g. architecture, infrastructure or even organizational level.

Perform further tests only on user's request.

## Observations, facts, predictions

Brief, 1-2 sentence statements with concrete findings, measurements and subjects. No fluff, no verbose paragraphs.

Predictions are **conditional** sentences, not true statements.

# Investigation scope

# Causal path

Causal path is a chain of actions contained within system components, whose execution leads to realize a functionality
and whose behavior is disrupted by the investigated issue. The causal path can be expanded with more detailed steps as
investigation progresses. Causal path is represented by sequence diagram, with additional activity, flowchart, state or
other diagram types as needed to further increase level of detail.

There can be more than one causal paths, if the investigation results warrants it. Examples include asynchronous systems
or organizational level problems.

# Core analysis loop

A hypothesis-driven-debugging is a iterative-recursive investigation method by repeatadly establishing facts from prior
evidence, forming new hypotheses and testing them in order to support or contradict based on the current state.

Conceptually, the loop can be modeled as recursive function in pseudo Elixir:

```elixir
def investigate() do
  investigate(initial_facts_and_symptoms(), [])
end

@type TestMethod :: %{..., type: :observational | :experimental }
@type Fact :: %{description: string(), derived_from: [Observation]}
@type Hypothesis :: %{description: string(), formed_based_on: [Fact | Hypothesis]}
@type Prediction :: %{description: string(), hypothesis: Hypothesis}
@type Observation :: %{description: string(), hypothesis: Hypothesis, evidenced_by: TestMethod(), origin_prediction: Prediction}
@type Conclusion :: %{description: string(), based_on: [Fact]}

def investigate(facts) do
  hypotheses = form_hypotheses(facts)

  predictions = Enum.flat_map(hypotheses, &form_predictions(&1))

  observations = Enum.flat_map(predictions, &test_prediction(&1))

  new_facts = Enum.flat_map(observations, &establish_facts(&1))

  investigate(fact ++ new_facts)
end

def test_prediction(prediction) do
  select_suitable_methods(prediction, observational_methods() ++ experimental_methods())
  |> Enum.map(&TestMethod.apply(&1))
end

```

## 1. Establish facts

First step is to establish what is known about the system at current point of the investigation, This includes both the
initial observations (the symptoms) and subsequent discoveries as more experiments are performed.

## 2. Form hypothesis and predictions

Hypothesis is a falsifable explanation of a system behavior that is based on established so far facts. Prediction is a
expected observation derived from hypothesis, refined, confirmed or contradicted by performing actual testing.

One hypothesis may form multiple predictions, each branching off to exercise different perspectives of the hypothesis.

## 3. Test the prediction

Perform one or more observational or interventional actions that will support or contradict the prediction. Utilize
methods and tools described in `tools-and-methods.md`.

## 4. Compare the outcome and note down observations

Compare the outcome - does it support the prediction, refines it or completely contradicts it?

Write down observations that are a result of the experiment.

## 5. Establish facts

Observations are bounded to the run experiment or observational method, while facts are derived statements explaining
the system behavior or its components. There can be zero or many facts derived from multiple observations. Facts should
be written in form that describes the system, not what was observed as part of the testing methods.

## 6. Draw conclusions or repeat

With enough facts, it's possible to draw conclusions about the actual causes, establish new, derived hypotheses or
perform further experiments.

Concluctions drawn from facts established by different experiments must not be contradictory. Conclusions however can
provide more that one, distinct actual cause (e.g. different parts of the system).

# Record file

Maintain a record file during the investigation. The file should contain following sections:

- brief description of the issue,
- ASCII tree for reference
- detailed record of each hypothesis observation.
-

```
# Title

Description and exptected vs reproduced behavior

hypothesis evaluation
├─ H1 hypothesis claim
├─ H2 hypothesis claim
│  ├─ E
│  ├─ H2.1 subhypothesis claim
│  │  ├─ hypothesis1 (#)[#Link to section]
...

# Causal path

Context description.

Embedded mermaid diagrams of causal path.

# Category 1

## Subcategory 2

### Hypothesis 1

Description of the hypothesis, observations and actions performed that support or contradict it, evidence in the form of commands, established flows.

...

```
