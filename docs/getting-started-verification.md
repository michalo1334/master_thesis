# Local setup verification

This records an actual local trial, not a guarantee for every host. The README is the short procedure; [infrastructure](infrastructure.md) explains configuration and teardown.

## Environment and isolation

The trial used Linux, Docker 28.3.3, and the repository's Dockerized Terraform helper. A host Terraform, Elixir, Erlang, Node, or PostgreSQL installation was not used to provision the stack. Python 3 decoded the configuration-derived secret file list.

Source came from a clean Git archive of `5ef2a5073fad040a493ca3add4515e3e1567eb84`. It did not copy application data, secrets, Terraform state, dependencies, build output, or `node_modules` from the working checkout. The Docker daemon and its image cache were shared with the host; this was not an empty-machine or cold-image-cache test.

To avoid the existing stack, only the temporary snapshot's deployment name and six published ports changed. The test used prefix `network-defense-setup-smoke` and ports 18400–18405. These are trial values, not required defaults. Before creation, the host had about 13 GiB memory and 33 GiB disk available. These observations are not minimum requirements.

## Commands and observed outcomes

Commands ran from `infra/environments/local/` in the temporary snapshot.

| Step | Command / action | Observed result |
| --- | --- | --- |
| Initialize | `./terraform.sh init` | Exit 0 |
| Validate | `./terraform.sh validate` | Exit 0 |
| Derive secret paths | Feed `jsonencode([local.secret_mount_path, local.required_secret_files])` to `./terraform.sh console -no-color` | Exit 0 before secrets existed; returned directory and ten required paths |
| Prepare secrets | Decode the console result and create random, owner-only files | Fresh files, not copies from the existing stack |
| Review plan | `./terraform.sh plan` | Initial successful plan: 54 creates, no changes or destroys |
| Provision | `./terraform.sh apply` with the reviewed isolated plan | Final attempt exit 0; failed isolated resources were replaced |
| Check drift | `./terraform.sh plan -detailed-exitcode` | Exit 0; no changes |
| Discover endpoints | `./terraform.sh output` | Published URLs returned |
| Check application | HTTP requests to `/healthz`, `/readyz`, and `/` | All returned 200; root contained LiveView markup |

All four new app containers became healthy. HTTP readiness alone did not prove a usable dashboard: the subsequent browser check found the origin defect below.

## Failures encountered

The first temporary archive was extracted under `umask 077`. That made source directories unreadable to non-root container users. RabbitMQ could not read its plugin configuration, and the analysis service could not traverse its package directory. Two apply attempts failed.

The trial restored normal source permissions in the temporary snapshot, retained owner-only permissions on secrets, and recreated only the failed isolated resources. The final apply succeeded. Use restrictive permissions for secrets, not for the entire source checkout. No application-source fix was required for HTTP readiness.

The pre-existing development stack remained untouched. Its app logs reported that `config/config.exs` changed while Phoenix was running and required a restart. Its HTTP failures were not used as clean-install evidence.

## Browser-origin defect found by the trial

The first browser attempt stayed on “Loading dashboard…” despite healthy HTTP endpoints. Phoenix's static URL and Vite's CORS/HMR settings still pointed to port 4000 instead of the configured public port. The browser requested assets from the wrong stack.

The documentation branch fixes that mismatch: Terraform passes the public port to the app, and development Phoenix and Vite use it with the configured host. Container listeners and default published ports remain unchanged. The change does not alter production Endpoint configuration.

After applying only the isolated app changes, health checks and Vite assets returned 200. CORS matched the isolated origin, and a fresh browser reached “Canvas ready.” Default and nondefault configuration checks passed, malformed ports failed, and nine existing RuntimeConfig tests passed. The remaining favicon 404 is nonblocking. A subsequent fresh browser session completed the simulation and optimization journey below.

## Exercised browser journey

A fresh browser at 1600×1000 opened the smallest seeded enterprise graph through **Create document → Graph**. The graph had 53 nodes, 71 edges, no unplaced entities, and no placement issues. Its initial revision was `5b787394-ea85-488f-9988-0df6416b7217` in the disposable database.

The user-facing controls ran a simulation from `workstation-4`, with 100 trials, 100 iterations, seed 0, and Random unchecked. The completed report showed mean blast radius 2.61 of 16 hosts and mean mission impact 0. These are recorded demonstration results, not research conclusions. The seeded title counts enterprise hosts; the report also includes the external host.

The same base graph then ran CVSS optimization with an action budget of 3. The completed report used all three actions and listed vulnerability patches. No API injection, database seeding beyond the normal setup, mocked responses, or fabricated results were used for the journey. The UI did not expose a run ID; report titles and graph/revision identity were recorded instead.

The main agent repeated the journey and captured all three README images at 1600×1050. The topology view uses Arrange, detailed zoom, and a search-selected host. Host/service labels, connections, and mission context are readable. Result notifications were closed and confirmed hidden before capture; all three images were visually inspected.

The final console recorded a favicon 404 and an ECharts zero-size warning while switching report views. Neither blocked the demonstrated operations or result tables. Other chart and browser workflows were not exhaustively tested.

## Evaluation configuration capture

The fourth README image shows a saved evaluation manifest in Preview. It displays the strategy matrix, budgets, selection seeds, and planned comparisons. The main agent entered and saved the example through the real UI, then reopened it for capture. The image is not evidence of completed evaluation or study results.

A real evaluation attempt stayed at 106 of 706 steps. Application logs recorded `consumer_cancelled` from RabbitMQ scatter-gather, followed by an evaluation experiment failure. The main agent cancelled that run through the UI. The root cause remains unverified; no backend or infrastructure fix was included in this documentation revision.

The screenshot is 1600×1050 and contains no injected results or modified DOM/CSS. Capture scripts, snapshots, and failure logs are under the gitignored `local-results/readme-revision/` directory.

## Evidence locations

Raw local logs are under `/tmp/master-thesis-setup-evidence/`, including `setup.txt`, `console.log`, `final-apply.log`, `post-apply-plan.log`, and `final-verification.log`. They are scratch files, not portable project artifacts. The observations above preserve their relevant results without publishing secrets or Terraform state.

Public-port evidence is under `/tmp/master-thesis-public-port-*`. Final browser replay, snapshots, and console output are under the gitignored `local-results/goal-verification/own-browser/` directory.

The secret helper was separately tested against real Terraform console output in a clean, tracked-file export. It created ten owner-only files; a second run preserved them byte-for-byte. Syntax checks and negative traversal, symlink, and permissive-file cases passed. No existing secrets or `.env` files were copied. Its report is under `local-results/goal-verification/secret-bootstrap-evidence/`.

The documentation branch's full `mix precommit` passed: formatting, contract generation, Svelte checking, asset builds, Credo, Dialyzer, Sobelow, and 861 tests passed, with three opt-in tests excluded. An isolated PostgreSQL container was used and removed. Raw output is `local-results/goal-verification/docs-check/precommit.log`. Local documentation links and images were checked against actual files; the external repository URL returned HTTP 200.
