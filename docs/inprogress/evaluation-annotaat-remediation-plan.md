# Annotaat remediation plan

**Date:** 2026-10-18

**Status:** Implemented and verified

**Worktree:** `/home/michalo/master_thesis-evaluation-rebuild`

**Annotation source:** `# Annotaat Export.md`

## Intent

Repair the confirmed boundary defects in the Stage 2 comparison prototype. Remove local duplication without creating a second contract system. Keep the scientific method, Gust orchestration, and stateless Python computation unchanged.

The user reviewed the annotations by category, approved the decisions below, and later approved implementation in the existing worktree.

## Execution instructions

- Implement in the existing worktree. Preserve pre-existing changes. Do not reset the tree or use another worktree.
- Execute directly. Do not spawn implementation agents or use delegation.
- Do not commit or push.
- Do not run Terraform apply or destroy. Implementation approval does not approve either operation.
- Use unit tests when they are simple. Use manual checks when automation requires a new or sophisticated harness.
- Use manual Terraform validation/plan, image-trigger, container-startup, and real HTTP/Gust checks. Do not add provider mocks, a custom Dockerfile parser, or another integration framework.
- Keep existing tests. Update expectations affected by the approved contract change. Do not delete tests merely because they are not unit tests.
- Record actual verification results separately from planned checks. Never report an unrun check as passed.
- If a blocked check needs unavailable infrastructure, access, or separate approval, report the blocker and completed evidence. Do not weaken the check.

## Authority and approved amendments

Read these documents before implementation:

- `docs/inprogress/evaluation-stage-2-design.md`
- `docs/inprogress/evaluation-rebuild-plan.md`
- The preserved methodology referenced by those documents.

The following decisions amend the earlier Stage 2 error-handling and validation layout. They do not change the scientific method:

1. Schema failures use **bounded nested validator diagnostics in the public error contract**. Do not translate them into application-specific issue codes or normalized typed instance paths.
2. The existing domain and operational issue forms remain available.
3. Cross-runtime conformance for schema failures checks acceptance/rejection and the permitted error form. It no longer requires equal schema issue codes, paths, or messages between libraries.
4. Custom changeset checks may call the canonical JSON Schema validator on the original input. They must not reproduce schema constraints.
5. Request-dependent result relations use one custom changeset validation function.
6. Python uses required `os.environ` reads without defaults. Do not introduce a settings class, generic reader framework, or custom `require_*` functions.
7. Use manual checks instead of adding complex test infrastructure.
8. Existing prototype encryption keys may change. No key migration or preservation project is required. Do not rotate a key without a reason for this work.

### Preserved constraints

- Keep canonical checked-in Draft 4 schemas as the wire authority.
- Keep Ecto for typed materialization and changeset coordination, not a second implementation of wire rules.
- Keep strict rejection of coercion, non-string/atom input keys, invalid numeric tokens, and non-finite values.
- Keep Gust responsible for orchestration, retries, and persistence.
- Keep Python synchronous, stateless, and compute-only.
- Preserve the approved 2 s connection timeout, 60 s response timeout, 1 MiB request limit, 64 KiB response/failure-envelope limits, and 240 s command wait limit.
- Do not change scientific defaults, sampling, random streams, calculation, or interpretation.
- Do not add production rollout work, generic configuration/error registries, source generation, or a replacement scheduler.
- Do not fork or patch Gust. No ExJsonSchema dependency patch is needed under the approved diagnostic-path decision.

## Effort and documentation

- **Level:** MVP.
- **Verification:** Thorough coverage of the changed boundaries; unit tests where simple, manual checks elsewhere.
- **Documentation:** This plan and executable unit tests. Record manual commands, inputs, expected outcomes, and actual results in the implementation handoff. Do not add a speculative backlog or rewrite the methodology.

## Confirmed evidence

Line references describe the inspected worktree before remediation. They can move during implementation.

| Area | Confirmed cause and evidence |
|---|---|
| Application image triggers | `infra/modules/local/app/main.tf:9-33` hashes selected files and `priv`. `src/Dockerfile.dev:39-64` copies more inputs. `infra/modules/local/app/locals.tf:15-25` mounts only selected source paths. `assets/svelte.config.js` is copied but neither mounted nor hashed. |
| Compute image triggers | `infra/modules/local/evaluation_compute/main.tf:3-6` enumerates source files without corresponding cache exclusions. Check against `services/evaluation_compute/Dockerfile` and `.dockerignore`. |
| Deployment enforcement | Compute `main.tf:9-22` and root `main.tf:26-36` use warning-only `check` blocks for required invariants. Compute `variables.tf` lacks integer/positive validation for several existing inputs. Module Terraform minimum is 1.9; the root pins a newer version. |
| Python startup | `services/evaluation_compute/src/evaluation_compute/run.py:8-18` supplies defaults and parses integers without explicit range checks. `api.py` independently reads request/logging defaults. `logging_config.py` also supplies a fallback level. |
| Response roots | `comparison/client.ex:40-68` decodes any JSON root. `schema_validator.ex:21-23` accepts maps only. The client-wide rescue at `client.ex:36-37` turns the resulting exception into temporary unavailability. |
| Schema diagnostics | `schema_validator.ex:38-51` converts numeric-looking keys to indexes. Its `allOf` mapping at lines 95-109 assigns a cause from the path rather than the nested failure. Pinned ExJsonSchema 0.11.5 constructs unescaped property paths in `src/deps/ex_json_schema/lib/ex_json_schema/validator/properties.ex:40-72`. |
| Duplicate relations | `client.ex:73-84` and `workflow.ex:105-115` repeat interval ordering and request-echo checks. |
| Serialization | `comparison/wire.ex` repeats nested contract fields. Existing `src/lib/network_defense/contracts.ex:51-58` already provides recursive string-key serialization. |
| Gust discovery | `comparison/dag_parser.ex` advertises `.exs`. Pinned Gust's built-in parser advertises `.ex`; its folder loader selects files through that callback. |

Comparison paths in this document refer to `src/lib/network_defense/evaluation/comparison/` unless stated otherwise.

## Approved architecture

```text
Original caller input
  -> JSON compatibility and encoded-size checks
  -> schema-backed custom changeset check on ORIGINAL input
  -> Ecto materialization
  -> comparison-local domain checks
  -> canonical serialization and outgoing-size check
  -> Gust submission

Python response / stored statistics
  -> canonical schema check on ORIGINAL decoded value
  -> Ecto materialization
  -> shared statistics changeset relation validation
  -> caller-specific handling

Validator failures
  -> bounded JSON-safe diagnostics
  -> ComparisonError
  -> HTTP or Gust envelope
```

Do not encode/decode or cast raw input into a normalized replacement before schema validation.

## Area A — Terraform values, image triggers, and deployment enforcement

### Ownership

- Local `.tfvars` files supply concrete deployment values.
- The compute module validates its own inputs.
- The root owns cross-service port collisions.
- Dockerfiles own build operations and COPY inputs.
- Existing runtime mount definitions remain the single source for mounted-path classification.

### Keep existing choices

- Keep the configured image name as an input. Do not add a dev/prod selector.
- Keep `GUST_ROLE=core` fixed. Application `ROLE` and Gust role have different concerns.
- Keep explicit Terraform-to-container environment mapping.
- Keep the Python standard-library readiness command and container loopback address.
- Keep host-access outputs bound to loopback. Do not expose them through an arbitrary bind-address input.

### Application image trigger

Modify `infra/modules/local/app/main.tf` and `locals.tf`.

Use this policy:

```text
trigger files = Dockerfile + context rules
              + copied files not replaced by host source mounts
              + dependency-preparation exceptions
trigger hash = sorted [relative filename, content hash] pairs
```

Derive host source mounts from `dev_mounts`; do not duplicate that list. Named build/dependency volumes are not host source mounts.

- Enumerate copied directories so newly added unmounted assets are covered automatically.
- Cover unmounted `assets/svelte.config.js`, `assets/tsconfig.json`, vendor/public files, and other effective unmounted assets.
- Keep dependency manifest and lockfile coverage.
- Keep `config/config.exs` and `config/dev.exs` coverage because they precede dependency compilation.
- Keep coverage of the explicitly early-copied runtime configuration module used by build-time compilation.
- Remove blanket hashing of mounted `priv` source after checking recompilation of embedded schema/resources.
- Do not rebuild for ordinary mounted Elixir, test, JS, CSS, and Svelte source edits.
- Runtime-only mounted configuration can need a restart without needing an image rebuild.
- Remove the telemetry exception only after checking that the existing startup/recompilation path handles it. Keep any proven build exception explicit.
- Account for `.dockerignore` exclusions within copied inputs. Do not hash generated artifacts Docker does not consume.

The copied-input classification must be reviewed when Dockerfile COPY instructions or mounts change. Use manual change-and-plan checks; do not implement a Dockerfile parser.

### Compute image trigger

Modify `infra/modules/local/evaluation_compute/main.tf` and, where needed, `services/evaluation_compute/.dockerignore`.

- Keep Dockerfile, `.dockerignore`, dependency manifests/locks, and effective package source in the trigger.
- Make nested cache exclusions explicit and align trigger filtering with them.
- Do not rebuild for excluded cache files or tests outside the image inputs.
- Do not restrict the trigger to Python extensions: package resources under `src` also matter.
- Do not change Docker build/run topology.

### Blocking module validation

Modify compute `variables.tf`; remove `check "site_inputs_match"` from compute `main.tf`.

Use blocking variable validation supported by the existing Terraform minimum:

- `site_networks` keys equal declared `sites` keys.
- `host_ports` keys equal declared `sites` keys.
- Compute host ports are unique.
- Container and host ports are integers in 1..65535.
- Worker count and request-limit bytes are positive integers.
- Required inputs are non-null.
- Log level is supported by the existing Uvicorn/logging stack.

Do not add arbitrary worker caps or new knobs. The approved configured request limit remains 1 MiB. Shutdown timeout is currently a fixed environment value, not a new Terraform variable.

Remove redundant compute-port range validation from the root object once the module owns it. Keep root input types.

### Cross-service collision enforcement

Modify `infra/environments/local/main.tf` and `variables.tf` as needed.

Replace the warning-only root host-port invariant with blocking root validation. Reuse `local.all_host_ports`; do not create a second allocation list. The root knows about application, database, observability, and compute ports. The compute module does not.

### Alternatives rejected

- Hashing the repository: unnecessary mounted-source rebuilds.
- Adding only the missing Svelte configuration file: leaves the maintenance defect.
- Mounting every build input: changes dependency/startup behavior beyond scope.
- Keeping required conditions as `check` assertions: warnings are insufficient.
- Attaching input validity only to per-site containers: enforcement must not depend on instances existing.
- Replacing the three site maps with a new configuration model: unnecessary interface change.

### Compatibility and rollback

Valid module callers retain the same interface. Invalid inputs fail earlier. No new resource or state migration is intended. Trigger hash changes can cause image changes in a later plan; this plan does not authorize apply. Roll back trigger/enforcement edits without deleting volumes or changing state.

## Area B — Python startup without defaults

### Files and ownership

- `services/evaluation_compute/src/evaluation_compute/run.py`: launcher settings.
- `api.py`: request-size enforcement.
- `logging_config.py`: logging setup.
- `services/evaluation_compute/Dockerfile`: image-level health command.
- Existing Python tests and demonstration startup inputs: explicit test configuration.

### Actions

- Use `os.environ[...]` for required settings. Missing values fail naturally.
- Use `int(...)` for integer settings. Malformed values fail naturally.
- Keep only necessary inline checks: port range, positive workers, positive shutdown seconds, positive request-limit bytes, and non-empty bind host.
- Require an explicit log level in logging setup. Let the logging stack reject unsupported levels.
- Do not duplicate request-limit parsing in the launcher and API. The API owns this setting.
- Remove fallback reads from both `run.py` and `api.py`, not just the launcher.
- Configure logging in the processes that need it; spawned workers must not depend on inherited parent logging state.
- Do not catch expected missing/malformed configuration exceptions merely to replace their messages.
- Do not catch arbitrary programming exceptions as configuration errors.
- Make the image health command read required `EVALUATION_PORT`, without a fallback. Keep Python stdlib and loopback.
- Supply required environment values explicitly in tests and manual service starts.

No new `runtime_config.py`, settings class, `require_*` functions, registry, or package is required.

### Compatibility and rollback

Terraform already supplies the settings. Manual starts and tests that relied on defaults need explicit environment values. Keep the configured shutdown and request limits unchanged. Roll back startup code and its harness inputs together. No database migration is involved.

## Area C — Elixir runtime configuration and discovery

### Actions

- Keep DNSCluster under Gust. Do not restore the duplicate application child.
- Keep `DNS_CLUSTER_QUERY` passed to Gust through runtime configuration.
- Remove duplicate comparison base-URL and Gust key assignments from `src/config/config.exs`.
- Keep runtime URL/key selection in `src/config/runtime.exs`.
- Preserve the site-local environment URL and existing direct-development loopback behavior.
- Keep production secret requirements. Do not add production rollout design.
- The user permits prototype key changes; no key migration project is needed. This cleanup does not itself require a key rotation.
- Do not make application startup contact Python. Unrelated application paths must remain usable without the compute service.

### Alternatives rejected and impact

A second DNSCluster child duplicates discovery and can conflict on the default registered name. A global compute-availability startup requirement would couple unrelated features to the prototype. Keep the resolved runtime behavior unchanged unless a separately identified defect requires a change. Roll back configuration assignments as a local unit.

## Area D — Schema-backed changesets and result relations

### Schema check

Add a comparison-local `matches_schema(changeset, raw, kind)` helper in `SchemaValidator`.

- Delegate to the canonical schema validator.
- Run on original input before `cast` or `cast_embed` can normalize it.
- Return the changeset.
- Attach the typed public error as changeset metadata when validation fails. Do not lose nested diagnostics.
- Accept syntactically valid decoded JSON roots of any type at the validator entry point. The canonical schema rejects invalid roots without a function-clause exception.
- Do not implement an allowed-key validator, schema compiler, or per-field schema checks in Ecto.

### Statistics contract

Modify `contracts/comparison_statistics.ex`.

- Provide one schema-backed parsing entry point used by both HTTP and stored-result callers.
- Materialize only after schema success.
- Implement one custom changeset `validate_result_relations` function.
- Check interval ordering, confidence-level echo, and test-alternative echo.
- Remove the private predicate copies from `Client` and `Workflow`.
- Skip relation evaluation when prior changeset stages are invalid.
- Keep caller-specific error classification outside the shared predicate.

The client maps result parse failure to permanent `invalid_response_contract`. Stored-result read-back rejects an invalid stored result. These are different boundaries using the same rule implementation.

### Request contract and public context

Modify `contracts/comparison_request.ex` and `src/lib/network_defense/evaluations.ex`.

Move request-boundary checks into the contract's changeset pipeline:

1. Reject non-string keys recursively before serialization.
2. Check JSON compatibility and original encoded size.
3. Call `matches_schema` against the original input.
4. Materialize through Ecto.
5. Run one custom crossed-evidence validation for existing plan-ID and alignment rules.
6. Check canonical outgoing size with the same size-check implementation.
7. Return the accepted typed request or typed `ComparisonError`.

Keep `Evaluations` responsible for calling the parser, serializing the accepted value, and submitting it to `Workflow`. Keep its existing typed public result convention; do not send changesets to Gust or Python.

Do not modify the shared `NetworkDefense.Contracts` macro for comparison-specific behavior.

### Alternatives and compatibility

Do not validate after casting, normalize input through a JSON round trip, or rely on Ecto casts to enforce exact JSON types. Valid submission behavior remains unchanged. Direct parser callers gain the same protections. Keep checks connected during the move; do not remove old protections before their replacements are used.

## Area E — Public nested schema diagnostics

### Approved contract shape

The following example illustrates the approved shape, not a fixture to paste into production source:

```json
{
  "schema_version": 1,
  "error": {
    "code": "validation_failed",
    "schema_errors": [
      {
        "message": "Validator explanation.",
        "path": "#/example",
        "causes": []
      }
    ]
  }
}
```

- Permit a clear schema-diagnostic form alongside the existing issue form.
- A validation failure uses schema diagnostics OR existing domain issues. Do not emit ambiguous mixed forms.
- Operational errors keep their existing issue form and top-level codes.
- Native paths are diagnostics, not normalized typed public paths. Python may retain native location segments; Elixir may retain the library's path string. The canonical diagnostic shape must permit the supported representations without reconstructing container types.
- Preserve nested causes when supplied. Do not invent nesting for a validator that reports a flat list.
- Bound diagnostic count, messages, and serialization. Preserve existing byte limits. Prevent nested causes from bypassing the total diagnostic budget.
- Exclude input values, exception dumps, stack traces, and unsafe context. Python must not copy Pydantic `input`, context, or diagnostic URLs wholesale into public responses.
- Do not serialize raw Elixir structs directly to JSON. Use a small JSON-safe adapter and the library's safe formatter/messages where appropriate.
- If bounded diagnostics cannot fit, use a small valid safe error form rather than leaking data or emitting invalid JSON. Keep HTTP classification consistent with the failure; diagnostic truncation must not turn invalid input into a successful result.

### Files and actions

- Canonical schema: `contracts/evaluation/comparison/v1/schemas/error.schema.json` and its existing application placement mechanism.
- Elixir: `contracts/comparison_error.ex`, `schema_validator.ex`, `wire.ex`, `task_failure.ex`, affected output/consumer code.
- Python: `contracts/errors.py`, `error_mapping.py`, and affected API error construction.
- Fixtures: shared `valid`/`invalid` examples and expected error forms.
- Terminal consumer: `src/lib/mix/tasks/evaluation.compare.ex` and the comparison workflow as needed.

Keep request/statistics schemas unchanged. Retain Draft 4 and checked-in authority. Do not generate source.

Delete schema-specific `enum_code`, `type_code`, `last_segment`, and typed-path normalization code. Remove the identical `type_code` branch through this deletion. Do not relabel all `allOf` failures as unsupported strategy.

### Compatibility

This is a deliberate breaking prototype error-format change. Update both runtimes and consumers together. Keep the prototype schema version as reviewed; do not introduce deployment-version management or a compatibility framework. Old stored errors that do not validate may produce the existing safe `workflow_failed` fallback. No migration or data deletion is required.

### Accepted diagnostic limitation

ExJsonSchema 0.11.5 does not escape property names correctly in returned paths. There is no current upstream fix in the reviewed release. The user chose diagnostic native paths instead of typed normalized paths. Therefore:

- no dependency patch;
- no tree traversal to infer types;
- no path-repair heuristics;
- no duplicate allowed-key validation.

This limitation is accepted, not repaired. Preserve validity decisions and do not claim exact normalized paths for these diagnostics.

## Area F — Client classification, errors, and serialization

### Client

Modify `client.ex`.

- Name the fixed endpoint and approved timeout/size defaults with local module attributes.
- Keep existing test timeout overrides. Do not add deployment knobs.
- Use the shared statistics entry point and error-envelope entry point.
- Arrays, strings, numbers, booleans, and null in success/error responses must become permanent `invalid_response_contract`.
- Retain malformed JSON, oversized body, and invalid-envelope rejection.
- Valid 400/413/415/422 errors are permanent.
- Valid 500/503 errors are temporary.
- Unknown HTTP statuses and invalid envelopes are permanent contract failures.
- Keep broad `{:error, reason}` transport-result handling; do not enumerate a small list of network reasons.
- Remove the rescue around the whole `compare/1` function.
- If raised transport exceptions need handling, catch only supported Req transport/protocol exception types around the HTTP call. Do not mask parsing, configuration, or programming errors as unavailability.

### Error construction

Use named constructors in the existing `ComparisonError` module for repeated locally produced errors, including invalid response, unavailable compute, request too large, and safe workflow failure.

- Callers do not repeat public code strings.
- Fixed atoms are suitable for internal changeset/control metadata.
- Public JSON keys and codes remain strings.
- Do not create atoms from external strings.
- Do not add a global list/registry duplicating the schema's allowed error codes.

### Serialization

Modify `wire.ex`.

- Reuse existing contract `to_params/1` for validated request and statistics structs.
- Remove manual nested request/statistics maps and `side/1`.
- Keep only the necessary error-envelope wrapper and active-form selection.
- Do not repeat issue/diagnostic field mapping in multiple serializers.
- Do not apply this serializer to raw caller input before validation.
- Check canonical schema conformance and absence of struct/Ecto metadata in unit tests.

### Alternatives and rollback

Reject broad exception masking, another generic error registry, another recursive encoder, and encode/decode normalization. Valid response classifications remain unchanged. The statistics entry point, client change, and schema validator root handling form one rollback unit. Error consumers and serializers roll back with the public error-contract change.

## Area G — Gust adapters and persistence

### DAG parser

Keep `dag_parser.ex`. It advertises `.exs` and delegates parsing to Gust. Do not rename the approved DAG merely to remove this adapter. Keep `prepare`, `compare`, and `store_result` behavior.

### Task failure adapter

Modify `task_failure.ex` where needed.

- Keep Gust-specific envelope kind/version, exception types, and byte limit local.
- Use named public error constructors.
- Add one `ComparisonError.parse_envelope/1` contract entry point. Both the client and persisted failure decoder use it; remove their repeated schema/materialization sequences.
- Preserve both permitted public error forms through persistence.
- Permanent failures raise `Gust.DAG.NonRecError`; temporary failures retain the existing retryable exception.
- Keep the prototype's existing three-attempt behavior. Do not change Gust scheduling or retry ownership.
- Keep encoding/size fallback behavior. Reject oversized persisted message input before parsing using the existing limit.
- Unknown/corrupt persisted failure data returns the safe workflow fallback.
- Never store a failure as a successful comparison result.

No Gust fork, migration, or new persistence mechanism is needed. Roll back error-consumer changes with the revised error contract.

## Verification plan

**Mode:** U = focused unit test; M = manual verification. Existing regression tests remain in place. Do not create a complex harness to automate M cases.

For manual checks, record the test ID, preconditions, input/change, command or action, expected outcome, actual outcome, and cleanup. Use temporary inputs/state copies or isolated containers as appropriate. Do not modify live Terraform state, apply/destroy resources, delete volumes, or stop unrelated services.

### Build policy — manual

| ID | Mode | EARS requirement |
|---|---|---|
| BUILD-01 | M | WHEN an unmounted copied asset changes, THE application image trigger SHALL change. |
| BUILD-02 | M | WHEN an ordinary mounted source file changes, THE application image trigger SHALL remain unchanged. |
| BUILD-03 | M | WHEN a dependency-preparation input changes, THE application image trigger SHALL change. |
| BUILD-04 | M | WHEN an image-only file is added, deleted, or renamed, THE application image trigger SHALL change. |
| BUILD-05 | M | WHEN Dockerfile COPY instructions change, THE input review SHALL identify trigger or mount coverage for each effective input. |
| BUILD-06 | M | WHEN excluded Python cache files change, THE compute image trigger SHALL remain unchanged. |
| BUILD-07 | M | WHEN effective Python package source or resources change, THE compute image trigger SHALL change. |
| BUILD-08 | M | WHEN mounted compile inputs change, THE development startup SHALL use the updated source. |

Use representative unmounted assets, mounted source, dependency files, schema resources, and telemetry. Compare trigger values/plans in a safe temporary input setup. BUILD-05 is a review checklist, not a proposed Dockerfile parser.

### Terraform — manual

| ID | Mode | EARS requirement |
|---|---|---|
| TF-01 | M | WHEN site-network keys are missing or extra, THE module plan SHALL fail. |
| TF-02 | M | WHEN host-port keys are missing or extra, THE module plan SHALL fail. |
| TF-03 | M | WHEN compute sites share a host port, THE module plan SHALL fail. |
| TF-04 | M | WHEN a port is fractional, null, or outside 1..65535, THE module plan SHALL fail. |
| TF-05 | M | WHEN worker count is zero, negative, fractional, or null, THE module plan SHALL fail. |
| TF-06 | M | WHEN request-limit bytes are zero, negative, fractional, or null, THE module plan SHALL fail. |
| TF-07 | M | WHEN a compute host port conflicts with another service, THE root plan SHALL fail. |
| TF-08 | M | WHEN the approved valid configuration is supplied, THE configuration SHALL pass validation and planning. |
| TF-09 | M | WHEN log level is unsupported, THE module plan SHALL fail. |

Run configuration validation and value-specific plans. `terraform validate` alone does not prove blocking input behavior. Do not add `.tftest.hcl` suites or provider mocks for this work. Preserve the approved separate state-location and apply gate.

### Python startup — unit and manual

| ID | Mode | EARS requirement |
|---|---|---|
| START-01 | U | WHEN a launcher-owned required setting is absent, THE launcher SHALL fail before starting Uvicorn. |
| START-02 | U | WHEN a numeric setting is malformed or outside its permitted range, THE owning startup code SHALL reject it. |
| START-03 | U | WHEN bind host is empty or log level is unsupported, THE startup code SHALL reject it. |
| START-04 | U | WHEN configuration is valid, THE launcher SHALL pass its settings to Uvicorn unchanged. |
| START-05 | M | WHEN the approved container configuration is supplied, THE container SHALL become ready. |
| START-06 | M | WHEN any required container setting is missing, THE service SHALL fail startup without becoming ready. |
| START-07 | M | WHEN a valid non-default port is supplied, THE image health check SHALL probe that port. |

Use ordinary environment patching and a stubbed Uvicorn call for simple units. For API-owned settings, test their direct parsing without building a new launcher/configuration framework. Use isolated process/container checks where import or multiprocessing behavior makes a unit artificial.

### Elixir configuration — unit or manual

| ID | Mode | EARS requirement |
|---|---|---|
| CONFIG-01 | U/M | WHEN a compute URL is supplied, THE resolved client configuration SHALL use it. |
| CONFIG-02 | U/M | WHEN local development omits the URL, THE existing loopback behavior SHALL remain unchanged. |
| CONFIG-03 | U/M | WHEN a dedicated Gust secret is supplied, THE resolved key SHALL use that source. |
| CONFIG-04 | U/M | WHEN only the application secret is supplied, THE resolved key SHALL use that source. |
| CONFIG-05 | M | WHEN required production secrets are absent, THE configuration SHALL reject startup. |
| CONFIG-06 | M | WHEN discovery is enabled, THE node SHALL have one DNSCluster process owned by Gust. |
| CONFIG-07 | M | WHEN Python is unavailable, THE application SHALL remain able to start without a comparison request. |

Use an existing simple configuration-reading test pattern if available. Otherwise inspect/evaluate the configuration manually; do not build a subprocess configuration framework.

### Client and relations — unit where simple

Use existing `comparison_client_test.exs`, contract tests, and workflow tests. Keep their existing HTTP stub rather than introducing another transport harness. If a case needs new substantial integration machinery, perform it manually.

| ID | Mode | EARS requirement |
|---|---|---|
| HTTP-01 | U/M | WHEN any non-object JSON root is received, THE client SHALL return permanent invalid_response_contract. |
| HTTP-02 | U/M | WHEN a documented error status has an invalid envelope, THE client SHALL return permanent invalid_response_contract. |
| HTTP-03 | U/M | WHEN HTTP 500 or 503 has a valid error envelope, THE client SHALL retain temporary classification. |
| HTTP-04 | U/M | WHEN Req returns a transport error, THE client SHALL return temporary compute_unavailable. |
| HTTP-05 | U | WHEN a programming or configuration exception occurs, THE client SHALL NOT relabel it compute_unavailable. |
| REL-01 | U | WHEN an existing result relation fails, THE shared changeset validation SHALL reject the result. |
| REL-02 | U/M | WHEN an HTTP result violates a relation, THE client SHALL reject it. |
| REL-03 | U/M | WHEN a stored result violates a relation, THE workflow SHALL reject it. |

Cover arrays, strings, numbers, booleans, and null under 200, 400, 413, 415, 422, 500, and 503. Retain malformed JSON, oversized response, unknown status, connection, and timeout regressions. Do not narrow transport handling to only the reasons used by a test.

### Schema diagnostics — unit

Earlier SCHEMA-01 through SCHEMA-07 proposed normalized public paths/causes. They are superseded by the user-approved diagnostic format. Do not implement their path-repair/dependency-patch approach.

| ID | Mode | EARS requirement |
|---|---|---|
| SCHEMA-08 | U | WHEN schema validation fails, THE response SHALL contain diagnostics accepted by the canonical error schema. |
| SCHEMA-09 | U | WHEN the validator supplies nested causes, THE diagnostics SHALL retain them within the payload limits. |
| SCHEMA-10 | U | WHEN either runtime processes a shared fixture, THE validity decision and error form SHALL match expectations. |
| SCHEMA-11 | U | WHEN diagnostics are serialized, THE payload SHALL exclude submitted values and internal exception data. |
| SCHEMA-12 | U | WHEN a domain rule fails, THE existing domain issue SHALL remain unchanged. |
| SCHEMA-13 | U | WHEN keys look numeric or contain slash/tilde, THE diagnostic adapter SHALL NOT invent normalized typed paths. |
| SCHEMA-14 | U | WHEN an allOf branch fails, THE adapter SHALL NOT replace its cause with an application-specific strategy label. |

Retain strict numeric-token, integer/boolean distinction, non-finite, unknown-field, and bounded-error coverage. Update shared expected fixtures for schema failures without asserting equality of library-specific diagnostics. Keep exact code/path expectations for existing domain issues.

### Serialization and request boundary — unit

| ID | Mode | EARS requirement |
|---|---|---|
| WIRE-01 | U | WHEN a request contract is serialized, THE output SHALL match its canonical JSON structure. |
| WIRE-02 | U | WHEN statistics are serialized, THE output SHALL pass the canonical statistics schema. |
| WIRE-03 | U | WHEN either error form is serialized, THE output SHALL pass the revised error schema. |
| WIRE-04 | U | WHEN a contract is serialized, THE output SHALL exclude Ecto metadata and struct markers. |
| WIRE-05 | U | WHEN raw input has atom keys, THE boundary SHALL reject it before normalization. |
| INPUT-01 | U | WHEN input has a non-string key at any depth, THE request parser SHALL reject it. |
| INPUT-02 | U | WHEN input contains an unsupported JSON value, THE request parser SHALL reject it. |
| INPUT-03 | U | WHEN original or outgoing JSON exceeds 1 MiB, THE request parser SHALL reject it. |
| INPUT-04 | U | WHEN a value requires coercion, THE schema check SHALL reject it before casting. |
| INPUT-05 | U | WHEN plan identities or column alignment are invalid, THE custom domain check SHALL reject the request. |
| INPUT-06 | U/M | WHEN public submission fails validation, THE system SHALL create no Gust run. |
| INPUT-07 | U/M | WHEN a request is valid, THE context SHALL submit only its accepted canonical representation. |

### Gust and real service — existing checks or manual

| ID | Mode | EARS requirement |
|---|---|---|
| GUST-01 | Existing/M | WHEN Gust scans the folder, THE adapter SHALL discover the approved EXS DAG. |
| GUST-02 | Existing/M | WHEN the DAG loads, THE definition SHALL retain prepare, compare, and result persistence. |
| GUST-03 | Existing/M | WHEN either public error form passes through persistence, THE decoded error SHALL retain that form. |
| GUST-04 | U | WHEN an encoded failure exceeds 64 KiB, THE adapter SHALL emit the small safe fallback. |
| GUST-05 | U/M | WHEN persisted failure data is corrupt, oversized, or unsupported, THE workflow SHALL return a safe failure. |
| GUST-06 | Existing/M | WHEN a failure is permanent or temporary, THE adapter SHALL preserve approved retry behavior. |
| DEMO-01 | M | WHEN the approved synthetic request runs through real HTTP and Gust, THE stored statistics SHALL be read back successfully. |
| DEMO-02 | M | WHEN the same scientific request is recomputed, THE statistics SHALL be identical. |
| DEMO-03 | M | WHEN invalid alignment is submitted, THE system SHALL store no successful comparison result. |

Use the existing `mix evaluation.compare` fixture path and existing demonstration/test entry points. Do not substitute an HTTP stub for the real-service demonstration. Do not apply infrastructure merely to complete a check; report a blocked managed demonstration if approval is still required.

## Implementation sequence and rollback units

The main agent executes these steps directly. These are implementation steps, not delegated jobs.

| Step | Actions and references | Verification and rollback boundary |
|---|---|---|
| 1 | Define the revised error schema and examples in `contracts/evaluation/comparison/v1`. Follow the existing error schema/fixture structure, not source generation. | Both permitted error forms validate. Review the breaking prototype change before consumers use it. |
| 2 | Update `ComparisonError`, Python error models/mapping, `SchemaValidator`, `Wire`, `TaskFailure`, and terminal consumers. Use existing constructors/serialization patterns and the diagnostic shape above. | Unit diagnostics/serialization checks; persisted round trip. Treat schema and consumers as one rollback unit. |
| 3 | Add original-input `matches_schema` checks and request/statistics changeset entry points. Follow current embedded-schema materialization in contract modules. | Strict-input and relation units. Remove duplicate checks only once callers use the shared entry points. |
| 4 | Update `Client` classification and local constants. Preserve broad Req error tuples; remove the whole-function rescue. | Existing client checks plus invalid-root and programmer-error regressions. Roll back with validator/contract call changes if needed. |
| 5 | Simplify `Evaluations`, named error construction, and duplicate runtime assignments. Keep Gust parser/discovery adapters. | Boundary units and manual app startup. Do not rotate keys or change unrelated features. |
| 6 | Replace Python defaults with direct required reads and necessary inline checks. Update explicit test/manual environments and image health port. | Simple units; manual startup/readiness. Startup changes and explicit environments roll back together. |
| 7 | Add blocking module/root validation; remove warning-only required checks and redundant compute range checks. | Manual invalid/valid plans. No new resources or apply/destroy. |
| 8 | Correct image trigger accounting and cache exclusions. Derive mounted paths from existing mount definitions. | Manual change-and-plan and source-recompile checks. Do not delete volumes. |
| 9 | Run existing regression checks and real HTTP/Gust demonstration where available. Record actual results and blockers. | Persisted result, repeatability, invalid evidence, and unrelated application regressions. Stop at any unresolved failure. |

Do not treat passing a local unit suite as proof of Terraform enforcement, container startup, or native scheduler persistence.

## All 24 original annotations

Paths and line numbers identify the original export. Short comparison paths refer to the directory defined above.

**Change** means required behavior work. **Cleanup** means an approved local simplification. **Keep** means no functional change for that annotation.

| # | Original annotation | Disposition | Concrete action |
|---:|---|---|---|
| 1 | `src/lib/network_defense/application.ex:46` — DNS query | Keep | Gust owns the one DNSCluster child. Do not restore another child. |
| 2 | `infra/environments/local/local.auto.tfvars:20` — image name | Keep | Keep existing module input. No dev/prod selector. |
| 3 | Same file, line 21 — log level | Change | Keep the input and add module validation. |
| 4 | `infra/modules/local/app/locals.tf:65` — Gust role | Keep | Keep core fixed; application ROLE has a different concern. |
| 5 | App `main.tf:9` — development trigger | Change | Cover effective unmounted/build inputs without ordinary mounted-source rebuilds. |
| 6 | Compute `main.tf:9` — site checks | Change | Use blocking input validation; include existing numeric invariants. |
| 7 | Compute `main.tf:42` — env mapping | Keep | Keep explicit deployment-to-environment mapping. |
| 8 | Compute `main.tf:68` — Python readiness check | Keep | Keep stdlib and container loopback. |
| 9 | Compute `outputs.tf:13` — loopback URL | Keep | Preserve local-only host access and variable ports. |
| 10 | Python `run.py:9` — defaults | Change | Required os.environ reads; necessary inline checks; no settings framework. |
| 11 | `src/config/config.exs:33` — key and URL | Cleanup | Remove duplicate runtime assignments. |
| 12 | `src/config/runtime.exs:188` — key and URL | Keep | Retain runtime ownership and approved local behavior; no key-migration work. |
| 13 | `client.ex:20` — endpoint string | Cleanup | Local named endpoint attribute. |
| 14 | `client.ex:26` — timeout values | Cleanup | Local named approved defaults; retain test overrides. |
| 15 | `client.ex:51` — validation/materialization/relations | Change | Schema-backed changesets; permanent invalid-root rejection; no whole-function transport masking. |
| 16 | `client.ex:86` — error strings | Cleanup | Named ComparisonError constructors; wire strings at the boundary. |
| 17 | `dag_parser.ex:1` — adapter necessity | Keep | Keep EXS discovery and delegate parsing to Gust. |
| 18 | `schema_validator.ex:1` — mapping size | Change | Replace schema-specific public issue mapping with bounded native diagnostics. |
| 19 | `schema_validator.ex:90` — causes and paths | Change | Preserve diagnostics without invented typed paths or strategy labels. |
| 20 | `task_failure.ex:48` — string errors | Change + cleanup | Named constructors and persistence of the revised public error form. |
| 21 | `wire.ex:1` — manual encoding | Change + cleanup | Existing recursive serialization plus necessary error wrapping. |
| 22 | `workflow.ex:104` — relation validation | Cleanup | Call the shared statistics changeset parser; delete predicate copy. |
| 23 | `src/lib/network_defense/evaluations.ex:9` — changesets | Change | Move request checks into the contract; keep submission in the context. |
| 24 | Same file, line 68 — error keys/codes | Cleanup | Internal metadata and named constructors; JSON string keys from serialization. |

Related confirmed work: exclude Python caches from triggers; block cross-service host collisions; remove the image health command's independent port assumption; remove the identical type-code branch; share error-envelope parsing.

## Premortem and accepted risks

| Risk or assumption | Treatment |
|---|---|
| Only some consumers adopt the error format. | Update schema, both runtimes, serializers, Gust adapter, and terminal output as one unit. |
| Casting makes invalid input look valid. | Validate original input before casting or normalization. Preserve strict units. |
| Trigger exclusions leave stale compiled code. | Check mounted source/resource recompilation manually before removing exceptions. |
| Validator paths remain ambiguous for numeric/slash/tilde names. | Accepted as diagnostic text. No typed-path guarantee or dependency patch. |
| Old prototype failures cannot be decoded. | Safe workflow fallback. No migration or destructive cleanup. |
| Native diagnostics expose data or exceed size limits. | Small JSON-safe adapter, bounded output, and safe fallback. Do not export raw validator objects wholesale. |
| Manual checks are not reproducible. | Record IDs, inputs, commands, expected and actual results. Do not add a complex harness. |
| Required infrastructure is unavailable without apply approval. | Mark the specific check blocked and report the input/approval needed. Do not apply or weaken acceptance. |

## Final acceptance and stop condition

The implementation is complete only when:

- Required invariants block invalid Terraform plans.
- Trigger checks distinguish effective image inputs, runtime mounts, and ignored caches.
- Python requires its environment settings without custom configuration infrastructure.
- Non-object response roots are permanent contract failures.
- Schema-backed changesets validate original input without duplicate wire rules.
- Result relations have one changeset implementation used at both boundaries.
- Nested schema diagnostics, existing domain issues, and operational errors pass their canonical contracts.
- Both runtimes and Gust/terminal consumers support the selected error forms.
- Strict numeric/key/value rejection and the scientific method remain unchanged.
- Simple units pass, existing regression checks are addressed, and manual results or blockers are recorded honestly.
- No apply/destroy, unrelated destructive action, commit, push, production rollout, registry, or generated evaluation source occurs.

If a requirement cannot be met without changing the approved scientific/contract scope, stop with the evidence, attempted path, blocker, and exact decision needed.

## Execution record

The original planner produced this design from the worktree, approved documents, schemas, fixtures, tests, and pinned dependency source. Later implementation passes followed the project delegation workflow. A final read-only audit found five high-value issues. The implementation then added bounded persisted-diagnostic parsing, guarded result relations, malformed `Content-Length` rejection, complete compute-image trigger inputs, and input-level Terraform validation.

The completed implementation and verification evidence are in `evaluation-annotaat-remediation-handoff.md`. No Terraform apply or destroy, commit, push, secret change, or unrelated cleanup occurred.
