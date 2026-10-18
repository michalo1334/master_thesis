# Evaluation annotation remediation handoff

**Status:** Implemented and verified

## Outcome

The remediation keeps the corrected crossed-bootstrap method and Gust workflow unchanged. It hardens the contract, compute-service, persistence, and local deployment boundaries.

The implementation does not add a study system, a result table, a Python job registry, source generation, or a generic configuration framework.

## Implemented changes

### Contract diagnostics

- The canonical error schema now supports two mutually exclusive error forms:
  - existing domain and operational `issues`;
  - nested validator `schema_errors`.
- Both forms have bounded text, paths, list sizes, and total entry counts.
- Schema diagnostics keep native validator paths. The adapter does not infer whether a numeric-looking property name is an array index.
- The public payload excludes submitted values, exception data, and stack traces.
- Elixir stops persisted diagnostic traversal after the total budget. This prevents a deeply nested failure envelope from causing unbounded recursive validation.
- Python and Elixir accept the same shared valid error fixtures.

### Parsing and response classification

- Request and statistics parsing now start with the canonical JSON Schema and then use Ecto changesets for materialization.
- Request validation uses the original caller value before canonical serialization.
- Result-relation checks have one implementation in the statistics changeset. The HTTP client and stored-result reader use this implementation.
- All syntactically valid non-object JSON response roots are permanent `invalid_response_contract` failures. This rule also applies to HTTP 500 and 503 responses.
- The client only classifies Req transport failures as temporary unavailability. It does not relabel programming errors.

### Serialization and Gust failures

- Request and statistics serialization use the shared recursive contract serializer.
- Error serialization preserves either `issues` or `schema_errors`.
- HTTP failures and persisted Gust failures use the same error-envelope parser.
- Gust failure decoding rejects messages above the existing byte limit before JSON decoding.
- Terminal output supports both public error forms.

### Python startup and request handling

- The compute service requires all startup environment settings.
- Port, worker count, shutdown timeout, request limit, bind host, and log level are validated before server startup.
- Docker supplies all required environment settings and uses Python for its readiness check.
- Malformed `Content-Length` values are rejected as invalid JSON. Declared and streamed request sizes remain bounded.

### Terraform validation and image triggers

- Port, worker-count, request-limit, site-key, and related invariants use blocking input-variable validation.
- Global host ports must be pairwise unique.
- Site, network, compute URL, primary-site, and node-site keys must agree.
- The application image trigger derives mounted source paths from the existing mount specification. It hashes copied inputs that runtime mounts do not replace, plus dependency-build inputs.
- The compute image trigger hashes all effective files copied from `src`. It excludes Python caches ignored by `.dockerignore`.

## Compatibility and migration

The error contract has one intentional compatibility change. Existing `issues` remain valid. Schema-validation failures now use `schema_errors` instead of synthetic application issue codes. Consumers must support both forms.

No database migration is required. Gust run parameters, task results, retry policy, task names, and DAG structure are unchanged. The statistical estimand, crossed resampling, confidence interval, null test, p-value, and interpretation rules are unchanged.

## Verification

The final verification covered:

- Python formatting and lint checks;
- 47 passing Python tests;
- 40 passing focused Elixir evaluation and Gust tests;
- the complete Elixir precommit suite: 457 passed and 2 existing RabbitMQ exclusions;
- warnings-as-errors compilation, Credo, Dialyzer, Sobelow, generated contracts, Prettier, Svelte checks, and asset builds;
- Terraform formatting and validation with Terraform 1.15.8;
- negative Terraform plans for zero workers, mismatched site keys, and duplicate host ports;
- a read-only Terraform plan against the current local state;
- Dockerfile checks for the application and compute images;
- an actual compute-image build, missing-environment startup failure, and successful readiness probe;
- whitespace and saved-plan checks;
- a final independent audit and correction recheck, with no remaining blocker.

The final Terraform plan proposes replacement of nine resources because both effective image hashes changed:

- the application image, setup container, and four application nodes;
- the compute image and two compute containers.

The plan reports `9 to add, 0 to change, 9 to destroy`. No plan was saved, and no apply or destroy was run.

## Accepted limits

- ExJsonSchema 0.11.5 does not escape slash and tilde characters in native diagnostic paths. These paths are diagnostic text, not typed JSON Pointer values.
- The Python tests report the existing Starlette AnyIO deprecation warning.
- The asset build reports the existing large-chunk warning.

## Operational state

No infrastructure change was applied. Running containers still use the prior images. Apply the reviewed replacement plan only after separate approval.

No commit or push was made. Secrets and unrelated worktree changes were not changed.
