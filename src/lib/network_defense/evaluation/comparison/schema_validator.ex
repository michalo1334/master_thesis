defmodule NetworkDefense.Evaluation.Comparison.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Evaluation.Comparison.Contracts.ComparisonError
  alias NetworkDefense.Evaluation.SchemaValidation

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/contracts/v1/schemas")
  @request_path Path.join(@schema_dir, "request.schema.json")
  @statistics_path Path.join(@schema_dir, "statistics.schema.json")
  @error_path Path.join(@schema_dir, "error.schema.json")
  @external_resource @request_path
  @external_resource @statistics_path
  @external_resource @error_path
  @request_schema SchemaValidation.resolve_contents(File.read!(@request_path))
  @statistics_schema SchemaValidation.resolve_contents(File.read!(@statistics_path))
  @error_schema SchemaValidation.resolve_contents(File.read!(@error_path))

  @spec validate(:request | :statistics | :error, term()) ::
          :ok | {:error, ComparisonError.t()}
  def validate(kind, value) do
    SchemaValidation.validate(
      value,
      fn -> schema(kind) end,
      &ComparisonError.schema_failure/1,
      fn -> safe_error(kind) end
    )
  end

  def matches_schema(%Changeset{} = changeset, raw, kind) do
    SchemaValidation.matches_schema(changeset, raw, kind, &validate/2, :comparison_error)
  end

  def error_from_changeset(%Changeset{} = changeset, fallback) do
    SchemaValidation.error_from_changeset(changeset, fallback, :comparison_error)
  end

  defp schema(:request), do: @request_schema
  defp schema(:statistics), do: @statistics_schema
  defp schema(:error), do: @error_schema

  defp generic_schema_error(message) do
    SchemaValidation.generic_schema_error(message, &ComparisonError.schema_failure/1)
  end

  defp safe_error(:request), do: generic_schema_error("Request validation failed safely.")
  defp safe_error(_kind), do: ComparisonError.invalid_response_contract()
end
