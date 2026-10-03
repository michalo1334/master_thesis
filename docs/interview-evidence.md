# Interview evidence: Elixir backend engineering

Use this repository to explain decisions, not to recite a technology list. For Driftrock, lead with message delivery, database consistency, and the browser-to-job boundary. The application is a research simulator, not a production customer-data service.

## A short walkthrough

### 1. Ship a feature across LiveView and the browser

Open the [dashboard LiveView](../src/lib/network_defense_web/live/web/dashboard/dashboard_live.ex) and [browser API](../src/assets/svelte/dashboard/dashboard-api.ts). Follow one request from the UI to a domain operation and back.

Evidence: [LiveView tests](../src/test/network_defense_web/live/dashboard_live_test.exs), [client API tests](../src/assets/svelte/dashboard/dashboard-api.test.ts), and the [dashboard workflow](design/dashboard.md).

Discuss why the project combines LiveView with Svelte rather than putting all interaction in either layer. The tradeoff is richer client interaction in exchange for an explicit event and payload boundary. This is LiveView experience, but not an example of a purely LiveView-rendered product.

### 2. Explain what a RabbitMQ acknowledgement means

In the [worker](../src/lib/network_defense/compute/rabbit_mq/worker.ex), valid work produces a result before acknowledgement. Publication or confirmation failure closes the channel without acknowledging the work. Redelivery can therefore repeat computation.

Evidence: [worker failure-path tests](../src/test/network_defense/compute/rabbit_mq/worker_test.exs), [envelope validation tests](../src/test/network_defense/compute/rabbit_mq/envelope_test.exs), and the opt-in [broker integration tests](../src/test/network_defense/compute/rabbit_mq_broker_integration_test.exs).

Discuss duplicates, bounded payloads, poison messages, and what publisher confirmation does—and does not—guarantee. Do not call this exactly-once delivery. See the [executor design](design/rabbitmq-distributed-executor.md) for the persistence boundary and broker exercise.

### 3. Protect a database state transition

The [evaluation-run store](../src/lib/network_defense/evaluation/evaluation_runs.ex) locks a row inside a transaction before completing, failing, or cancelling a running evaluation. A competing transition must observe the locked state rather than overwrite it blindly.

Evidence: the implementation above, [evaluation tests](../src/test/network_defense/evaluation_test.exs), and [graph persistence tests](../src/test/network_defense/graph/graph_test.exs). The graph tests cover a different persistence boundary; they are not proof of every run-state race.

Discuss locking versus optimistic updates, contention, rollback, and where a business invariant belongs. Explain how you would test two competing writers.

### 4. Separate durable orchestration from computation

Compare the [supervision tree](../src/lib/network_defense/application.ex), [Oban evaluation worker](../src/lib/network_defense/evaluation/evaluation_worker.ex), and RabbitMQ worker. The request process, persisted orchestration job, and distributed computation have different lifetimes.

Evidence: [evaluation progress tests](../src/test/network_defense/evaluation/evaluation_progress_test.exs) and the [evaluation lifecycle](concepts/evaluation.md).

Discuss retries, cancellation, recovery, and the authority for progress. A supervised process alone does not make its in-memory state durable.

### 5. Make failures observable without logging everything

Inspect [observability handling](../src/lib/network_defense/observability.ex) and its [tests](../src/test/network_defense/observability_test.exs). They cover structured OTP reports, task trace propagation, Prometheus metric types, and selection of Ecto metadata that omits query parameters.

Discuss which identifiers connect a request to background work, how metadata cardinality affects cost, and which payloads must stay out of logs. Unit tests of event formatting do not prove that a deployed collector delivers every signal.

### 6. Keep cross-language contracts in sync

The [contract generator](../src/lib/mix/tasks/gen.contracts.ex) derives browser types from [server contracts](../src/lib/network_defense_web/contracts.ex). The [generator tests](../src/test/network_defense_web/contracts_gen_test.exs) exercise that boundary.

Discuss one source of truth versus hand-maintained types, and why generation alone does not validate an untrusted runtime payload. Contract changes remain cross-stack changes.

## Testing, review, and AI judgment

Walk through an adverse case before a happy path: failed result confirmation, malformed input, or an invalid revision reference. Explain why it needs a unit test, an integration test, or a manual experiment.

The [saved review comments](../planning/pr1-review-comments.md) and [refactor plan](../planning/pr1-review-refactor-plan.md) show concrete requests to remove repeated traversal, reuse geometry helpers, and fix contract ownership. They are better evidence of review-driven maintenance than a claim that all code is “clean.”

Tests and commits do not prove TDD, pairing, personal authorship, or professional experience. Describe your own contribution accurately. If AI helped, explain which suggestions you rejected and how you verified accepted changes. Static checks support that judgment; they cannot identify AI authorship or replace review.

## Useful next exercises

These are proposed work, not completed portfolio claims:

- Demonstrate a duplicate-delivery case with one logical persisted outcome. Record the failure injection and the database result.
- Race completion and cancellation against the same evaluation. Explain the allowed result before writing the test.
- Capture one real request-to-job trace and audit it for sensitive fields. Compare the deployed trace with the unit-test expectations.

For Driftrock's Single Customer View work, discuss how these principles transfer to lead ingestion, deduplication, and identity reconciliation. This repository does not implement those product features. It also does not establish production scale, customer-data handling, Kubernetes, or GCP experience. Keep those gaps explicit.
