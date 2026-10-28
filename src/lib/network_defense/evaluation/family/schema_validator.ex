defmodule NetworkDefense.Evaluation.Family.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Evaluation.Family.Contracts.FamilyError
  alias NetworkDefense.Evaluation.SchemaValidation

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/family/v1/schemas")
  @request_path Path.join(@schema_dir, "request.schema.json")
  @holm_request_path Path.join(@schema_dir, "holm_request.schema.json")
  @holm_response_path Path.join(@schema_dir, "holm_response.schema.json")
  @result_path Path.join(@schema_dir, "result.schema.json")
  @error_path Path.join(@schema_dir, "error.schema.json")
  @external_resource @request_path
  @external_resource @holm_request_path
  @external_resource @holm_response_path
  @external_resource @result_path
  @external_resource @error_path

  @request_schema SchemaValidation.resolve_contents(File.read!(@request_path))
  @holm_request_schema SchemaValidation.resolve_contents(File.read!(@holm_request_path))
  @holm_response_schema SchemaValidation.resolve_contents(File.read!(@holm_response_path))
  @result_schema SchemaValidation.resolve_contents(File.read!(@result_path))
  @error_schema SchemaValidation.resolve_contents(File.read!(@error_path))

  @type kind :: :request | :holm_request | :holm_response | :result | :error

  @spec validate(kind(), term()) :: :ok | {:error, FamilyError.t()}
  def validate(kind, value) do
    SchemaValidation.validate(
      value,
      fn -> schema(kind) end,
      &FamilyError.schema_failure/1,
      fn -> safe_error(kind) end
    )
  end

  def matches_schema(%Changeset{} = changeset, raw, kind) do
    SchemaValidation.matches_schema(changeset, raw, kind, &validate/2, :family_error)
  end

  def error_from_changeset(%Changeset{} = changeset, fallback) do
    SchemaValidation.error_from_changeset(changeset, fallback, :family_error)
  end

  defp schema(:request), do: @request_schema
  defp schema(:holm_request), do: @holm_request_schema
  defp schema(:holm_response), do: @holm_response_schema
  defp schema(:result), do: @result_schema
  defp schema(:error), do: @error_schema

  defp generic_schema_error(message) do
    SchemaValidation.generic_schema_error(message, &FamilyError.schema_failure/1)
  end

  defp safe_error(:request), do: generic_schema_error("Family request validation failed safely.")
  defp safe_error(_kind), do: FamilyError.invalid_response_contract()
end
