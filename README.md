# Network Defense

If an attacker gets into a network, which defensive change helps most?

This master's thesis project lets you model a network, simulate attacks spreading through it, and compare defenses under the same action budget. Try patching vulnerabilities, blocking connections between segments, or revoking credentials. See which choices protect the capabilities the network needs to keep running—not just how many hosts remain uncompromised.

It is a research simulator, not a penetration-testing tool. Success probabilities are scenario inputs, not estimates of real-world exploit likelihood. Attack paths emerge during simulation; you do not need to enumerate them first.

## See it in action

### Model the network

Explore hosts and services inside their network segments. Save a revision so each run has a fixed, inspectable input.

![Network topology with hosts and services grouped into segments](docs/images/topology.png)

### See what an attack disrupts

Run repeated attacks and inspect mission impact, blast radius, and host compromise probabilities. A single lucky or unlucky run is not the whole picture.

![Completed attack simulation report](docs/images/simulation.png)

### Compare defensive changes

Choose a strategy and action budget, then inspect the selected defenses and the resulting graph revision.

![Completed defense optimization with selected actions](docs/images/defenses.png)

## Get started

Use Linux with Git, a running Docker engine, and Python 3. Terraform, Elixir, Node, and the databases run in containers. The local environment includes two application sites and observability services, so allow for a full development stack rather than a single-container demo.

```bash
git clone https://github.com/michalo1334/master_thesis.git
cd master_thesis/infra/environments/local
./terraform.sh init
./init-secrets.sh
./terraform.sh plan
./terraform.sh apply
./terraform.sh output urls
```

Review the plan before approving it. The secret helper creates missing random secret files with owner-only permissions; it preserves existing values. It reads the required paths from Terraform rather than keeping a second list.

Open the `application` URL printed by Terraform. For a small first run:

1. Choose **Create document → Graph**, then open **Enterprise Topology (15 hosts)**. Use **Arrange** to lay out the graph.
2. In **Simulation**, choose `workstation-4`, set 100 trials, 100 iterations, and seed 0, then **Simulate**.
3. Return to the graph tab. In **Optimization**, choose **CVSS**, set a budget of 3, and **Optimize**.

These are example inputs, not recommended research settings.

See [setup verification](docs/getting-started-verification.md) for the exercised environment and its limits. For configuration, port conflicts, and lifecycle details, use the [infrastructure guide](docs/infrastructure.md). Keep this development stack local; it is not a hardened public deployment.

To remove the stack, run `./terraform.sh destroy` from the same directory. **This deletes its database and other managed data volumes.** Host secret files remain.

## Roadmap

- Finish the cloud evaluation tooling: a one-off runner, topology diagnostics, environment records, and automatic warm-up.
- Run the frozen topology-scale study on Azure and publish the measured strategy comparisons.
- External vulnerability ingestion remains deferred; current evaluations use scenario data.

The [tooling plan](docs/inprogress/cloud-evaluation-tooling-plan.md) separates implemented work from blockers. Local pilot results are not final cloud-study evidence.

## Explore the project

- **Model:** [scope and limits](docs/concepts/scope.md), [requirements](docs/concepts/requirements.md), [graph and reachability](docs/concepts/graph.md), [attack simulation](docs/concepts/attack.md), [defenses](docs/concepts/defense.md).
- **Research workflow:** [evaluation and studies](docs/concepts/evaluation.md), [worked example](docs/concepts/model-example.md), [vocabulary](docs/concepts/vocabulary.md), [analysis guide](evaluation/analysis/README.md).
- **Engineering:** [architecture](docs/architecture.md), [dashboard](docs/design/dashboard.md), [RabbitMQ executor](docs/design/rabbitmq-distributed-executor.md), [interview evidence and tradeoffs](docs/interview-evidence.md).

The Elixir/Phoenix application and Svelte UI live in [`src/`](src/); analysis and scenarios in [`evaluation/`](evaluation/); provisioning in [`infra/`](infra/). [`docs/`](docs/) holds project documentation and [`planning/`](planning/) holds working plans. The thesis text is maintained separately.
