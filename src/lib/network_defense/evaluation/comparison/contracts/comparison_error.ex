defmodule NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  @max_entries 50
  @max_text_bytes 256

  @type t :: %__MODULE__{
          schema_version: integer(),
          code: String.t(),
          issues: [map()],
          schema_errors: [map()]
        }

  embedded_schema do
    field :schema_version, :integer, default: 1
    field :code, :string
    field :issues, {:array, :map}, default: []
    field :schema_errors, {:array, :map}, default: []
  end

  def changeset(error, attrs),
    do: cast(error, attrs, [:schema_version, :code, :issues, :schema_errors])

  def schema_failure(diagnostics),
    do: %__MODULE__{code: "validation_failed", schema_errors: diagnostics}

  def invalid_response_contract(
        message \\ "The compute service returned an invalid response contract."
      ),
      do: new("invalid_response_contract", "invalid_response_contract", [], message)

  def unavailable,
    do:
      new("compute_unavailable", "compute_unavailable", [], "The compute service is unavailable.")

  def workflow_failed(message \\ "The comparison workflow failed safely."),
    do: new("workflow_failed", "workflow_failed", [], message)

  def request_too_large(limit_bytes),
    do:
      new(
        "request_too_large",
        "request_too_large",
        [],
        "The request exceeds the byte limit.",
        %{"limit_bytes" => limit_bytes}
      )

  def invalid_json_value(path),
    do:
      new(
        "validation_failed",
        "invalid_type",
        path,
        "The request contains a value that is not valid JSON."
      )

  def parse_envelope(value) do
    alias NetworkDefense.Evaluation.Comparison.SchemaValidator

    with :ok <- preflight_diagnostic_budget(value),
         :ok <- SchemaValidator.validate(:error, value),
         do: materialize_envelope(value)
  end

  def materialize_envelope(%{"schema_version" => version, "error" => error} = envelope)
      when is_map(error) do
    code = error["code"]
    issues = Map.get(error, "issues")
    schema_errors = Map.get(error, "schema_errors")

    if preflight_diagnostic_budget(envelope) == :ok and
         is_binary(code) and valid_error_form?(code, issues, schema_errors) do
      {:ok,
       %__MODULE__{
         schema_version: version,
         code: code,
         issues: issues || [],
         schema_errors: schema_errors || []
       }}
    else
      {:error, :materialization_failed}
    end
  end

  def materialize_envelope(_value), do: {:error, :materialization_failed}

  def new(code, issue_code, path, message, details \\ %{}) do
    %__MODULE__{
      code: code,
      issues: [
        %{"code" => issue_code, "path" => path, "message" => message, "details" => details}
      ]
    }
  end

  defp valid_error_form?(_code, issues, nil) when is_list(issues) and issues != [] do
    length(issues) <= @max_entries and Enum.all?(issues, &valid_issue?/1)
  end

  defp valid_error_form?("validation_failed", nil, diagnostics)
       when is_list(diagnostics) and diagnostics != [] do
    within_diagnostic_budget?(diagnostics) and Enum.all?(diagnostics, &valid_diagnostic?/1)
  end

  defp valid_error_form?(_code, _issues, _diagnostics), do: false

  defp valid_issue?(%{"message" => message}) when is_binary(message),
    do: byte_size(message) <= @max_text_bytes

  defp valid_issue?(_issue), do: false

  defp valid_diagnostic?(%{"message" => message, "path" => path, "causes" => causes})
       when is_binary(message) and is_list(causes) do
    byte_size(message) <= @max_text_bytes and valid_diagnostic_path?(path) and
      Enum.all?(causes, &valid_diagnostic?/1)
  end

  defp valid_diagnostic?(_diagnostic), do: false

  defp valid_diagnostic_path?(path) when is_binary(path),
    do: byte_size(path) <= @max_text_bytes

  defp valid_diagnostic_path?(path) when is_list(path) do
    Enum.count_until(path, 33) <= 32 and
      Enum.all?(path, fn
        item when is_integer(item) -> true
        item when is_binary(item) -> byte_size(item) <= @max_text_bytes
        _item -> false
      end)
  end

  defp valid_diagnostic_path?(_path), do: false

  defp preflight_diagnostic_budget(%{"error" => %{"schema_errors" => diagnostics}})
       when is_list(diagnostics) do
    if within_diagnostic_budget?(diagnostics), do: :ok, else: {:error, :materialization_failed}
  end

  defp preflight_diagnostic_budget(_value), do: :ok

  defp within_diagnostic_budget?(diagnostics) do
    match?({:ok, _remaining}, consume_diagnostics(diagnostics, @max_entries))
  end

  defp consume_diagnostics([], remaining), do: {:ok, remaining}
  defp consume_diagnostics([_diagnostic | _rest], 0), do: :error

  defp consume_diagnostics([diagnostic | rest], remaining) when is_map(diagnostic) do
    causes = Map.get(diagnostic, "causes", [])

    with true <- is_list(causes),
         {:ok, remaining} <- consume_diagnostics(causes, remaining - 1),
         {:ok, remaining} <- consume_diagnostics(rest, remaining) do
      {:ok, remaining}
    else
      _invalid -> :error
    end
  end

  defp consume_diagnostics(_diagnostics, _remaining), do: :error
end
