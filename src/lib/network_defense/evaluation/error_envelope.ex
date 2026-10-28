defmodule NetworkDefense.Evaluation.ErrorEnvelope do
  @moduledoc false

  # Shared shape and budget rules for the bounded error envelope.
  #
  # The envelope has one error form: a non-empty `issues` list or a non-empty
  # `schema_errors` list. Each contract still owns its own schema and struct.

  @max_entries 50
  @max_text_bytes 256

  @type attrs :: %{
          schema_version: term(),
          code: String.t(),
          issues: [map()],
          schema_errors: [map()]
        }

  alias NetworkDefense.Evaluation.ContractSupport

  # These constructors receive trusted owner modules, not submitted values.
  def new(owner, code, issue_code, path, message, details) do
    struct!(owner,
      code: code,
      issues: [ContractSupport.issue(issue_code, path, message, details)]
    )
  end

  def materialize(owner, value) do
    with {:ok, attrs} <- materialize(value), do: {:ok, struct!(owner, attrs)}
  end

  def parse(owner, value, validate) do
    with {:ok, attrs} <- parse(value, validate), do: {:ok, struct!(owner, attrs)}
  end

  def request_size_details(limit_bytes, actual_bytes \\ nil) do
    if is_integer(actual_bytes) do
      %{"limit_bytes" => limit_bytes, "actual_bytes" => actual_bytes}
    else
      %{"limit_bytes" => limit_bytes}
    end
  end

  @spec body(term(), [map()], [map()], map()) :: map()
  def body(code, issues, schema_errors, fallback_body) do
    cond do
      issues != [] -> %{"code" => code, "issues" => issues}
      schema_errors != [] -> %{"code" => code, "schema_errors" => schema_errors}
      true -> fallback_body
    end
  end

  @spec parse(term(), (term() -> :ok | {:error, term()})) ::
          {:ok, attrs()} | {:error, term()}
  def parse(value, validate) do
    with :ok <- preflight(value),
         :ok <- validate.(value) do
      materialize(value)
    end
  end

  @spec preflight(term()) :: :ok | {:error, :materialization_failed}
  def preflight(%{"error" => %{"schema_errors" => diagnostics}}) when is_list(diagnostics) do
    if within_diagnostic_budget?(diagnostics), do: :ok, else: {:error, :materialization_failed}
  end

  def preflight(_value), do: :ok

  @spec materialize(term()) :: {:ok, attrs()} | {:error, :materialization_failed}
  def materialize(%{"schema_version" => version, "error" => error} = envelope)
      when is_map(error) do
    code = error["code"]
    issues = Map.get(error, "issues")
    schema_errors = Map.get(error, "schema_errors")

    if preflight(envelope) == :ok and is_binary(code) and
         valid_error_form?(code, issues, schema_errors) do
      {:ok,
       %{
         schema_version: version,
         code: code,
         issues: issues || [],
         schema_errors: schema_errors || []
       }}
    else
      {:error, :materialization_failed}
    end
  end

  def materialize(_value), do: {:error, :materialization_failed}

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
