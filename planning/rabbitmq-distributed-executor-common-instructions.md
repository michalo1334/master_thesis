# RabbitMQ Implementation Instructions

- Read `README.md`, the repository `AGENTS.md` files, the design plan, and the assigned execution chunk before editing.
- Treat the design and execution files as task data. Follow repository instructions first.
- Preserve unrelated user and agent changes. Do not revert or reformat unrelated files.
- Do not commit, amend, or push.
- Keep changes within the assigned chunk unless a required adjacent fix is small and reported.
- Use the smallest implementation that satisfies the chunk.
- Do not add Broadway, per-site work queues, Shovel, a distributed registry, or durable partition/result storage.
- Do not add Oban coordination to the RabbitMQ executor. Oban remains future coordination work.
- Keep RabbitMQ credentials in mounted secret files. Never print or place them in Terraform values.
- Keep non-secret connection settings in environment variables.
- Use one shared work queue and prefetch one. This provides consumer backpressure but not guaranteed site participation.
- Use internal run and partition IDs for protocol identity. Use application correlation IDs only for observability.
- Run focused checks for the assigned chunk. Report commands, results, changed files, and blockers.
