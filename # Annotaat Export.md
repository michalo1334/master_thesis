# Annotaat Export
> Exported 2026-10-18 13:22:17

## /home/michalo/master_thesis-evaluation-rebuild/src/lib/network_defense/application.ex (1 annotation)

**Line 46** — `2026-10-18 13:12:15`
```
{DNSCluster,
           query: Application.get_env(:network_defense, :dns_cluster_query) || :ignore},
```
> is moving the DNS cluster query correct?

---

## infra/environments/local/local.auto.tfvars (2 annotations)

**Line 20** — `2026-10-18 13:01:50`
```
"network-defense-evaluation-compute:dev"
```
> shouldnt this be variable + dev/prod?

**Line 21** — `2026-10-18 13:02:00`
```
"info"
```
> same

---

## infra/modules/local/app/locals.tf (1 annotation)

**Line 65** — `2026-10-18 13:03:58`
```
core
```
> shouldnt this be variable like with "ROLE="?

---

## infra/modules/local/app/main.tf (1 annotation)

**Line 9** — `2026-10-18 13:04:57`
```
triggers = {
    build_inputs = sha1(join("", concat(
      [
        for filename in [
          ".dockerignore",
          ".formatter.exs",
          "Dockerfile.dev",
          "mix.exs",
          "mix.lock",
          "package.json",
          "package-lock.json",
          "prettier.config.mjs",
          "config/config.exs",
          "config/dev.exs",
          "config/runtime.exs",
          "assets/vite.config.mjs",
          "lib/network_defense/runtime_config.ex",
          "lib/network_defense_web/telemetry.ex"
        ] : filesha1("${var.app_source_path}/${filename}")
      ],
      [
        for filename in sort(fileset(var.app_source_path, "priv/**/*")) :
        filesha1("${var.app_source_path}/${filename}")
      ]
    )))
```
> Is there better way (as in: established best practice) for handling build trigger for dev?

---

## infra/modules/local/evaluation_compute/main.tf (3 annotations)

**Line 9** — `2026-10-18 13:05:52`
```
check "site_inputs_match" {
  assert {
    condition = (
      toset(keys(var.sites)) == toset(keys(var.site_networks)) &&
      toset(keys(var.sites)) == toset(keys(var.host_ports))
    )
    error_message = "Sites, site networks, and evaluation-compute host ports must have identical keys."
  }

  assert {
    condition     = length(values(var.host_ports)) == length(distinct(values(var.host_ports)))
    error_message = "Evaluation-compute host ports must be unique."
  }
}
```
> I assume its the best practices to make sure site inputs match?? Or is there better terraform established practices? )

**Line 42** — `2026-10-18 13:06:27`
```
env = [
    "EVALUATION_BIND_HOST=0.0.0.0",
    "EVALUATION_PORT=${var.container_port}",
    "EVALUATION_REQUEST_LIMIT_BYTES=${var.request_limit_bytes}",
    "EVALUATION_WORKERS=${var.process_count}",
    "EVALUATION_LOG_LEVEL=${var.log_level}",
    "EVALUATION_SHUTDOWN_TIMEOUT_SECONDS=10"
  ]
```
> Initially I thought its inline env variables but I see its mapping TF vars to ENV vars, I assume its correct?

**Line 68** — `2026-10-18 13:07:00`
```
est         = ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${var.container_port}/ready', timeout=2)"]
```
> Do we have to use python? Is it simplest way to achieve it? Maybe curl? Also 127.0.0.1 is kinda hardcoded

---

## infra/modules/local/evaluation_compute/outputs.tf (1 annotation)

**Line 13** — `2026-10-18 13:07:17`
```
ttp://127.0.0.1
```
> hardcoded - is that ok?

---

## services/evaluation_compute/src/evaluation_compute/run.py (1 annotation)

**Line 9** — `2026-10-18 13:09:00`
```
log_level = os.getenv("EVALUATION_LOG_LEVEL", "info")
    configure_logging(log_level)
    uvicorn.run(
        "evaluation_compute.api:app",
        host=os.getenv("EVALUATION_BIND_HOST", "0.0.0.0"),
        port=int(os.getenv("EVALUATION_PORT", "8080")),
        workers=int(os.getenv("EVALUATION_WORKERS", "1")),
```
> hardcoded ENV values -> We risk if they change in TF they become invalid. Also default values - >remvoe. Fail fast

---

## src/config/config.exs (1 annotation)

**Line 33** — `2026-10-18 13:11:04`
```
nfig :network_defense, NetworkDefense.Evaluation.Comparison.Client,
  base_url: "http://127.0.0.1:8080"

config :gust,
  b64_secrets_cloak_key:
    "development-only-gust-key" |> then(&:crypto.hash(:sha256, &1)) |> Base.encode64(),
```
> Two isusesL 1. hardocded DEV key but config is used also for prod??? 2. base_url -> is hardocidng 127.0.0.1 and port correct?

---

## src/config/runtime.exs (1 annotation)

**Line 188** — `2026-10-18 13:11:20`
```
config :network_defense, NetworkDefense.Evaluation.Comparison.Client,
  base_url: System.get_env("EVALUATION_COMPUTE_URL", "http://127.0.0.1:8080")

gust_key_source =
  RuntimeConfig.read_secret("GUST_CLOAK_KEY") ||
    RuntimeConfig.read_secret("SECRET_KEY_BASE", "development-only-gust-key")

config :gust,
  b64_secrets_cloak_key: gust_key_source |> then(&:crypto.hash(:sha256, &1)) |> Base.encode64(),
  dags_folder: Application.app_dir(:network_defense, "priv/gust/dags"),
  dns_cluster_query: System.get_env("DNS_CLUSTER_QUERY")
```
> sameh here

---

## src/lib/network_defense/evaluation/comparison/client.ex (4 annotations)

**Line 20** — `2026-10-18 13:14:36`
```
"/v1/comparisons/corrected-crossed-bootstrap")
```
> hardcoded string

**Line 26** — `2026-10-18 13:14:53`
```
connect_timeout, 2_000)],
      receive_timeout: Keyword.get(config, :receive_timeout, 60_000),
```
> hardcoded values

**Line 51** — `2026-10-18 13:16:55`
```
fp parse_failure(status, body) do
    classification = if status in [500, 503], do: :temporary, else: :permanent

    if status in [400, 413, 415, 422, 500, 503] do
      with {:ok, decoded} <- decode_body(body),
           :ok <- SchemaValidator.validate(:error, decoded),
           {:ok, error} <- ComparisonError.materialize_envelope(decoded) do
        {:error, classification, error}
      else
        _error -> {:error, :permanent, invalid_response_error()}
      end
    else
      {:error, :permanent, invalid_response_error()}
    end
  end

  defp decode_body(body) when is_binary(body) and byte_size(body) <= @response_limit do
    Jason.decode(body)
  end

  defp decode_body(_body), do: {:error, :invalid_body}

  defp validate_relations(statistics, request) do
    interval = statistics.interval
    test = statistics.test

    if interval["lower"] <= interval["upper"] and
         interval["confidence_level"] == request.interval.confidence_level and
         test["alternative"] == request.test.alternative do
      :ok
    else
      {:error, :invalid_relations}
    end
```
> two issues: 1. validation utside changes set - schemavalidator - makes sense? 2. ComparisonError.materialize_envelope -> sounds weird 3. validate_relations -> validation for specific fields a) should it be here or either fail further or use ecto changesets?

**Line 86** — `2026-10-18 13:15:28`
```
defp invalid_response_error do
    ComparisonError.new(
      "invalid_response_contract",
      "invalid_response_contract",
      [],
      "The compute service returned an invalid response contract."
    )
  end

  defp unavailable_error do
    ComparisonError.new(
      "compute_unavailable",
      "compute_unavailable",
      [],
      "The compute service is unavailable."
```
> same - strings for errors

---

## src/lib/network_defense/evaluation/comparison/dag_parser.ex (1 annotation)

**Line 1** — `2026-10-18 13:17:18`
```
defmodule NetworkDefense.Evaluation.Comparison.DAGParser do
  @moduledoc false
  @behaviour Gust.DAG.Parser.Adapter

  alias Gust.DAG.Parser.Adapters.Elixir, as: ElixirParser

  @impl true
  def extension, do: ".exs"

  @impl true
  def parse_file(file_path) do
    ElixirParser.parse_file(file_path)
  end
```
> is it necessary?

---

## src/lib/network_defense/evaluation/comparison/schema_validator.ex (2 annotations)

**Line 1** — `2026-10-18 13:18:41`
```
defmodule NetworkDefense.Evaluation.Comparison.SchemaValidator do
  @moduledoc false

  alias ExJsonSchema.Schema
  alias ExJsonSchema.Validator
  alias ExJsonSchema.Validator.Error
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/contracts/v1/schemas")
  @request_path Path.join(@schema_dir, "request.schema.json")
  @statistics_path Path.join(@schema_dir, "statistics.schema.json")
  @error_path Path.join(@schema_dir, "error.schema.json")
  @external_resource @request_path
  @external_resource @statistics_path
  @external_resource @error_path

  @request_schema @request_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @statistics_schema @statistics_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @error_schema @error_path |> File.read!() |> Jason.decode!() |> Schema.resolve()

  @spec validate(:request | :statistics | :error, map()) ::
          :ok | {:error, ComparisonError.t()}
  def validate(kind, value) when is_map(value) do
    case Validator.validate(schema(kind), value, error_formatter: false) do
      :ok ->
        :ok

      {:error, errors} when is_list(errors) ->
        {:error, comparison_error(kind, errors)}

      {:error, _reason} ->
        {:error, internal_error(kind)}
    end
  rescue
    _exception -> {:error, internal_error(kind)}
  end

  def normalize_path("#"), do: []

  def normalize_path("#/" <> pointer) do
    pointer
    |> String.split("/", trim: false)
    |> Enum.map(fn part ->
      decoded = part |> String.replace("~1", "/") |> String.replace("~0", "~")

      case Integer.parse(decoded) do
        {integer, ""} -> integer
        _other -> decoded
      end
    end)
  end

  defp schema(:request), do: @request_schema
  defp schema(:statistics), do: @statistics_schema
  defp schema(:error), do: @error_schema

  defp comparison_error(kind, errors) do
    issues =
      errors
      |> Enum.flat_map(&issues_for(kind, &1))
      |> Enum.uniq_by(&{&1["path"], &1["code"]})
      |> Enum.sort_by(fn issue -> {path_sort_key(issue["path"]), issue["code"]} end)
      |> Enum.take(50)

    %ComparisonError{schema_version: 1, code: "validation_failed", issues: issues}
  end

  defp issues_for(_kind, %Error{error: %Error.Required{missing: missing}, path: pointer}) do
    path = normalize_path(pointer)

    Enum.map(missing, fn field ->
      issue("required_field_missing", path ++ [field], "This field is required.")
    end)
  end

  defp issues_for(_kind, %Error{error: %Error.AdditionalProperties{}, path: pointer}) do
    [issue("unknown_field", normalize_path(pointer), "Unknown field.")]
  end

  defp issues_for(kind, %Error{error: %Error.Type{}, path: pointer}) do
    [
      issue(
        type_code(kind, normalize_path(pointer)),
        normalize_path(pointer),
        "Invalid JSON type."
      )
    ]
  end

  defp issues_for(kind, %Error{error: %Error.Enum{}, path: pointer}) do
    path = normalize_path(pointer)
    [issue(enum_code(kind, path), path, "Unsupported value.")]
  end

  defp issues_for(:request, %Error{error: %Error.AllOf{}, path: pointer}) do
    path = normalize_path(pointer)

    if path == ["evidence", "alternative", "strategy"] do
      [
        issue(
          "unsupported_alternative_strategy",
          path,
          "The alternative strategy is not supported."
        )
      ]
    else
      [issue("workflow_failed", [], "Request validation failed safely.")]
    end
  end

  defp issues_for(kind, %Error{error: error, path: pointer})
       when is_struct(error, Error.Pattern) or is_struct(error, Error.MinLength) or
              is_struct(error, Error.MaxLength) do
    path = normalize_path(pointer)

    [
      issue(
        if(kind == :request, do: "invalid_identifier", else: fallback_code(kind)),
        path,
        "Invalid string value."
      )
    ]
  end

  defp issues_for(:request, %Error{error: %Error.MinItems{}, path: pointer}) do
    path = normalize_path(pointer)

    code =
      case last_segment(path) do
        "attack_seeds" -> "insufficient_attack_count"
        "plans" -> "insufficient_plan_count"
        _other -> "workflow_failed"
      end

    [issue(code, path, "The array does not contain enough values.")]
  end

  defp issues_for(:request, %Error{error: %Error.UniqueItems{}, path: pointer}) do
    path = normalize_path(pointer)

    code =
      if last_segment(path) == "attack_seeds",
        do: "duplicate_attack_seed",
        else: "workflow_failed"

    [issue(code, path, "Array values must be unique.")]
  end

  defp issues_for(:request, %Error{error: error, path: pointer})
       when is_struct(error, Error.Minimum) or is_struct(error, Error.Maximum) do
    [issue("invalid_analysis_setting", normalize_path(pointer), "Invalid analysis setting.")]
  end

  defp issues_for(kind, _error) do
    [issue(fallback_code(kind), [], "Contract validation failed safely.")]
  end

  defp type_code(:request, path) do
    if "mission_impacts" in path, do: "invalid_type", else: "invalid_type"
  end

  defp type_code(kind, _path), do: fallback_code(kind)

  defp enum_code(:request, ["schema_version"]), do: "unsupported_schema_version"
  defp enum_code(:request, ["evidence", "outcome"]), do: "unsupported_outcome"
  defp enum_code(:request, ["evidence", "reference", "strategy"]), do: "unsupported_reference"
  defp enum_code(:request, ["test", "alternative"]), do: "unsupported_test_alternative"
  defp enum_code(kind, _path), do: fallback_code(kind)

  defp last_segment([segment]), do: segment
  defp last_segment([_segment | rest]), do: last_segment(rest)

  defp fallback_code(:request), do: "workflow_failed"
  defp fallback_code(_kind), do: "invalid_response_contract"

  defp internal_error(:request) do
    ComparisonError.new(
      "workflow_failed",
      "workflow_failed",
      [],
      "Request validation failed safely."
    )
  end

  defp internal_error(_kind) do
    ComparisonError.new(
      "invalid_response_contract",
      "invalid_response_contract",
      [],
      "The compute service returned an invalid contract."
    )
  end

  defp issue(code, path, message, details \\ %{}) do
    %{"code" => code, "path" => path, "message" => message, "details" => details}
  end

  defp path_sort_key(path) do
    Enum.map(path, fn
      value when is_binary(value) -> {0, value}
      value when is_integer(value) -> {1, value}
    end)
  end
end
```
> Given we use ExjSOnSchema - a dedicated schema validator - do we need so much code here? What is going on even here?

**Line 90** — `2026-10-18 13:19:44`
```
defp issues_for(kind, %Error{error: %Error.Enum{}, path: pointer}) do
    path = normalize_path(pointer)
    [issue(enum_code(kind, path), path, "Unsupported value.")]
  end

  defp issues_for(:request, %Error{error: %Error.AllOf{}, path: pointer}) do
    path = normalize_path(pointer)

    if path == ["evidence", "alternative", "strategy"] do
      [
        issue(
          "unsupported_alternative_strategy",
          path,
          "The alternative strategy is not supported."
        )
      ]
    else
      [issue("workflow_failed", [], "Request validation failed safely.")]
    end
  end

  defp issues_for(kind, %Error{error: error, path: pointer})
       when is_struct(error, Error.Pattern) or is_struct(error, Error.MinLength) or
              is_struct(error, Error.MaxLength) do
    path = normalize_path(pointer)

    [
      issue(
        if(kind == :request, do: "invalid_identifier", else: fallback_code(kind)),
        path,
        "Invalid string value."
      )
    ]
  end

  defp issues_for(:request, %Error{error: %Error.MinItems{}, path: pointer}) do
    path = normalize_path(pointer)

    code =
      case last_segment(path) do
        "attack_seeds" -> "insufficient_attack_count"
        "plans" -> "insufficient_plan_count"
        _other -> "workflow_failed"
      end

    [issue(code, path, "The array does not contain enough values.")]
  end

  defp issues_for(:request, %Error{error: %Error.UniqueItems{}, path: pointer}) do
    path = normalize_path(pointer)

    code =
      if last_segment(path) == "attack_seeds",
        do: "duplicate_attack_seed",
        else: "workflow_failed"

    [issue(code, path, "Array values must be unique.")]
  end

  defp issues_for(:request, %Error{error: error, path: pointer})
       when is_struct(error, Error.Minimum) or is_struct(error, Error.Maximum) do
    [issue("invalid_analysis_setting", normalize_path(pointer), "Invalid analysis setting.")]
  end

  defp issues_for(kind, _error) do
    [issue(fallback_code(kind), [], "Contract validation failed safely.")]
  end

  defp type_code(:request, path) do
    if "mission_impacts" in path, do: "invalid_type", else: "invalid_type"
  end

  defp type_code(kind, _path), do: fallback_code(kind)

  defp enum_code(:request, ["schema_version"]), do: "unsupported_schema_version"
  defp enum_code(:request, ["evidence", "outcome"]), do: "unsupported_outcome"
  defp enum_code(:request, ["evidence", "reference", "strategy"]), do: "unsupported_reference"
  defp enum_code(:request, ["test", "alternative"]), do: "unsupported_test_alternative"
  defp enum_code(kind, _path), do: fallback_code(kind)

  defp last_segment([segment]), do: segment
  defp last_segment([_segment | rest]), do: last_segment(rest)

  defp fallback_code(:request), do: "workflow_failed"
  defp fallback_code(_kind), do: "invalid_response_contract"

  defp internal_error(:request) do
    ComparisonError.new(
      "workflow_failed",
      "workflow_failed",
      [],
      "Request validation failed safely."
    )
  end

  defp internal_error(_kind) do
    ComparisonError.new(
      "invalid_response_contract",
      "invalid_response_contract",
      [],
      "The compute service returned an invalid contract."
```
> 1. string errors 2. do we need mapping as function? 3. do we need such stuff as last_segment(path) == ... -> for me looks like duplicated vaidation AND it should be in ecto changeset

---

## src/lib/network_defense/evaluation/comparison/task_failure.ex (1 annotation)

**Line 48** — `2026-10-18 13:20:02`
```
ComparisonError.new(
        "workflow_failed",
        "workflow_failed",
        [],
        "The comparison w
```
> same here - string error

---

## src/lib/network_defense/evaluation/comparison/wire.ex (1 annotation)

**Line 1** — `2026-10-18 13:20:38`
```
defmodule NetworkDefense.Evaluation.Comparison.Wire do
  @moduledoc false

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics
  }

  def request(%ComparisonRequest{} = request) do
    %{
      "schema_version" => request.schema_version,
      "evidence" => %{
        "outcome" => request.evidence.outcome,
        "attack_seeds" => request.evidence.attack_seeds,
        "alternative" => side(request.evidence.alternative),
        "reference" => side(request.evidence.reference)
      },
      "resampling" => %{
        "seed" => request.resampling.seed,
        "replicates" => request.resampling.replicates
      },
      "interval" => %{"confidence_level" => request.interval.confidence_level},
      "test" => %{"alternative" => request.test.alternative}
    }
  end

  def statistics(%ComparisonStatistics{} = statistics) do
    %{
      "schema_version" => statistics.schema_version,
      "method" => statistics.method,
      "estimate" => statistics.estimate,
      "interval" => statistics.interval,
      "test" => statistics.test,
      "assessment" => statistics.assessment
    }
  end

  def error(%ComparisonError{} = error) do
    %{
      "schema_version" => error.schema_version,
      "error" => %{"code" => error.code, "issues" => error.issues}
    }
  end

  defp side(side) do
    %{
      "strategy" => side.strategy,
      "plans" =>
        Enum.map(side.plans, fn plan ->
          %{"id" => plan.id, "mission_impacts" => plan.mission_impacts}
        end)
    }
  end
end
```
> dont we have mechanism for automatic encoding instead of manually mapping fields??????

---

## src/lib/network_defense/evaluation/comparison/workflow.ex (1 annotation)

**Line 104** — `2026-10-18 13:21:20`
```
defp validate_result_relations(statistics, request) do
    interval = statistics.interval

    if interval["lower"] <= interval["upper"] and
         interval["confidence_level"] == request.interval.confidence_level and
         statistics.test["alternative"] == request.test.alternative do
      :ok
    else
      {:error, :invalid_relations}
    end
  end

  defp invalid_result_error do
    ComparisonError.new(
      "invalid_response_contract",
      "invalid_response_contract",
      [],
      "The stored comparison result is invalid."
    )
  end

  defp workflow_error do
    ComparisonError.new(
      "workflow_failed",
      "workflow_failed",
      [],
      "The comparison workflow failed safely."
    )
```
> same here

---

## src/lib/network_defense/evaluations.ex (2 annotations)

**Line 9** — `2026-10-18 13:13:35`
```
def submit_comparison(attrs) when is_map(attrs) do
    with :ok <- string_keys_only(attrs),
         {:ok, encoded} <- encode(attrs),
         :ok <- within_limit(encoded),
         {:ok, request} <- ComparisonRequest.parse(attrs),
         canonical = Wire.request(request),
         {:ok, canonical_encoded} <- encode(canonical),
         :ok <- within_limit(canonical_encoded) do
      Workflow.submit(canonical)
    end
  end

  def submit_comparison(_attrs), do: {:error, invalid_input_error([], "invalid_type")}

  def await_comparison(run_id, timeout_ms), do: Workflow.await(run_id, timeout_ms)
  def get_comparison_result(run_id), do: Workflow.result(run_id)

  defp string_keys_only(value), do: string_keys_only(value, [])

  defp string_keys_only(map, path) when is_map(map) do
    Enum.reduce_while(map, :ok, fn
      {key, value}, :ok when is_binary(key) ->
        case string_keys_only(value, path ++ [key]) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end

      {_key, _value}, :ok ->
        {:halt, {:error, invalid_input_error(path, "invalid_type")}}
    end)
  end

  defp string_keys_only(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case string_keys_only(value, path ++ [index]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp string_keys_only(_value, _path), do: :ok
```
> hmm, this smells like better would be to use Ecto changesets somehow??

**Line 68** — `2026-10-18 13:14:11`
```
ComparisonError.new(
         "request_too_large",
         "request_too_large",
         [],
         "The request exceeds the byte limit.",
         %{"limit_bytes" => @request_limit}
       )}
    end
  end

  defp invalid_input_error(path, code) do
    ComparisonError.new(
      "validation_failed",
      code,
      path,
      "The request contains a value that is not valid JSON."
    )
```
> error keys but they are 1. hardcoded strings inline, not defined in common module 2. not atoms

---
