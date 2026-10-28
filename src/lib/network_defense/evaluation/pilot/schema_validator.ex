defmodule NetworkDefense.Evaluation.Pilot.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError
  alias NetworkDefense.Evaluation.SchemaValidation

  @schema_dir Application.app_dir(:network_defense, "priv/evaluation/pilot/v1/schemas")
  @snapshot_path Path.join(@schema_dir, "snapshot.schema.json")
  @request_path Path.join(@schema_dir, "request.schema.json")
  @candidate_request_path Path.join(@schema_dir, "candidate_request.schema.json")
  @candidate_response_path Path.join(@schema_dir, "candidate_response.schema.json")
  @result_path Path.join(@schema_dir, "result.schema.json")
  @error_path Path.join(@schema_dir, "error.schema.json")
  @external_resource @snapshot_path
  @external_resource @request_path
  @external_resource @candidate_request_path
  @external_resource @candidate_response_path
  @external_resource @result_path
  @external_resource @error_path

  @snapshot_document @snapshot_path |> File.read!() |> Jason.decode!()
  @snapshot_schema SchemaValidation.resolve_document(@snapshot_document)

  # The stored payload has no metadata wrapper. Its schema is the documented
  # payload definition, resolved as its own draft-04 document.
  @payload_schema SchemaValidation.resolve_payload(@snapshot_document)

  @request_schema SchemaValidation.resolve_contents(File.read!(@request_path))
  @candidate_request_schema SchemaValidation.resolve_contents(File.read!(@candidate_request_path))
  @candidate_response_schema SchemaValidation.resolve_contents(
                               File.read!(@candidate_response_path)
                             )
  @result_schema SchemaValidation.resolve_contents(File.read!(@result_path))
  @error_schema SchemaValidation.resolve_contents(File.read!(@error_path))

  @type kind ::
          :snapshot
          | :snapshot_payload
          | :request
          | :candidate_request
          | :candidate_response
          | :result
          | :error

  @spec validate(kind(), term()) :: :ok | {:error, PilotError.t()}
  def validate(kind, value) do
    SchemaValidation.validate(
      value,
      fn -> schema(kind) end,
      &PilotError.schema_failure/1,
      fn -> safe_error(kind) end
    )
  end

  def matches_schema(%Changeset{} = changeset, raw, kind) do
    SchemaValidation.matches_schema(changeset, raw, kind, &validate/2, :pilot_error)
  end

  def error_from_changeset(%Changeset{} = changeset, fallback) do
    SchemaValidation.error_from_changeset(changeset, fallback, :pilot_error)
  end

  defp schema(:snapshot), do: @snapshot_schema
  defp schema(:snapshot_payload), do: @payload_schema
  defp schema(:request), do: @request_schema
  defp schema(:candidate_request), do: @candidate_request_schema
  defp schema(:candidate_response), do: @candidate_response_schema
  defp schema(:result), do: @result_schema
  defp schema(:error), do: @error_schema

  defp generic_schema_error(message) do
    SchemaValidation.generic_schema_error(message, &PilotError.schema_failure/1)
  end

  defp safe_error(:snapshot),
    do: generic_schema_error("Evidence snapshot validation failed safely.")

  defp safe_error(:snapshot_payload),
    do: generic_schema_error("Stored evidence payload validation failed safely.")

  defp safe_error(:request),
    do: generic_schema_error("Pilot request validation failed safely.")

  defp safe_error(_kind), do: PilotError.invalid_response_contract()
end
