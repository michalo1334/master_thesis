# RabbitMQ Distributed Executor Execution

## Chunk 1: Local RabbitMQ Infrastructure

Add a Terraform-managed RabbitMQ broker for the local environment.

Scope:

- Add one RabbitMQ module under `infra/modules/local`.
- Attach the broker to every site network and the observability network.
- Do not add a RabbitMQ data volume.
- Mount the broker password from a restrictive host secret file.
- Pass the host, AMQP port, virtual host, and username to application nodes as environment variables.
- Mount the same password file read-only into application nodes.
- Enable the RabbitMQ Prometheus plugin.
- Add a broker health check.
- Add the broker scrape target to central Prometheus.
- Add the RabbitMQ password to the local required-secret checks.
- Preserve all unrelated infrastructure changes.

Verification:

- Format and validate Terraform through the local helper.
- Check rendered environment and mount paths without printing secret contents.

## Chunk 2: Elixir AMQP Foundation

Add the application-level AMQP dependency, configuration, connection, and
message-contract foundation. Do not implement the consumer or coordinator.

Scope:

- Add the existing Hex `amqp` library. Do not add Broadway.
- Read RabbitMQ host, port, virtual host, username, password file, message-size limit, and result-inactivity timeout through runtime configuration.
- Add one supervised named AMQP connection on every application node.
- Reconnect after connection loss without terminating the application.
- Provide a minimal API for later worker and executor channels.
- Define versioned work and result envelopes.
- Encode envelopes with Erlang External Term Format.
- Check the raw payload size before decoding.
- Decode with `:erlang.binary_to_term/2` and the `:safe` option.
- Validate all fields after decoding.
- Map operation identifiers through a fixed allowlist that initially permits only the simulation operation.
- Keep the application correlation ID as observability data, not protocol identity.
- Add focused tests for configuration, round trips, malformed values, unknown versions, unknown operations, and oversized payloads.
- Do not switch the configured executor in this chunk.

Verification:

- Run focused tests for the new modules.
- Run compilation and formatting checks.

## Chunk 3: RabbitMQ Worker

Add one supervised worker consumer on each application node.

Scope:

- Open and monitor a dedicated worker channel.
- Declare the shared durable work queue with consistent arguments.
- Consume with manual acknowledgements and prefetch set to one.
- Validate messages before execution.
- Extract W3C trace context before the partition span starts.
- Execute each partition in a supervised task.
- Publish successful results and tagged errors before acknowledging work.
- Publish task exits as terminal compact errors without requeue.
- Leave work unacknowledged when result publication fails.
- Let RabbitMQ redeliver only after node, channel, or connection loss.
- Acknowledge and discard malformed or unsupported messages.
- Reopen the channel and resubscribe after recovery.

Verification:

- Test acknowledgement, terminal errors, task exits, malformed messages, and channel recovery.

## Chunk 4: RabbitMQ Coordinator And Direct Invocation

Implement the executor and switch simulation scatter-gather to direct,
supervised invocation without Oban coordination.

Scope:

- Implement `NetworkDefense.Compute.RabbitMQExecutor`.
- Generate one internal run ID and one partition ID per scattered item.
- Declare one transient, exclusive, auto-delete reply queue per run.
- Keep a global bounded publication window from `max_concurrency`.
- Match and deduplicate replies by run ID and partition ID.
- Preserve semantic partition keys for `gather/3`.
- Preserve empty-scatter, progress, error, gather, and unordered-result behavior.
- Apply the configured result-inactivity timeout only to expected result silence.
- Return `:result_timeout` when it expires.
- Delete the reply queue and close the channel during cleanup.
- Invoke the executor through a supervised ephemeral coordinator.
- Remove Oban from the simulation execution path without changing unrelated Oban users.
- Do not persist partitions or partial results.

Verification:

- Run shared executor contract tests and focused coordinator tests.
- Verify that no simulation execution path enqueues an Oban job.

## Chunk 5: Telemetry And Broker Observability

Extend tracing, metrics, and dashboards for distributed execution.

Scope:

- Propagate W3C trace context in work-message headers.
- Keep the run span on the coordinator and partition spans on workers.
- Add bounded payload-size and redelivery measurements.
- Keep partition keys and node names out of metric labels.
- Use collector-provided `site` and `replica` labels.
- Add RabbitMQ queue, consumer, delivery, acknowledgement, and redelivery panels.
- Keep central Prometheus as the direct RabbitMQ scraper.

Verification:

- Query metrics and traces from a running local environment.
- Confirm per-site and per-replica partition visibility.

## Chunk 6: Integration, Failure Checks, And Documentation

Complete cross-site verification and update public documentation.

Scope:

- Add a broker integration test for cross-site consumer eligibility.
- Verify worker-node loss and unacknowledged-message redelivery.
- Verify duplicate-result suppression.
- Verify task exits produce terminal errors without a requeue loop.
- Verify reply-queue deletion after normal completion and coordinator exit.
- Verify result timeout behavior.
- Update architecture, infrastructure, and public design documentation.
- State that a shared queue provides eligibility, not guaranteed site participation.
- State that durable coordinator recovery remains future work.

Verification:

- Run project precommit checks.
- Launch the local environment and perform the documented failure exercise.
