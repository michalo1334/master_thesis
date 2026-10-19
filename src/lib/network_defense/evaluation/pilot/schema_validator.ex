defmodule NetworkDefense.Evaluation.Pilot.SchemaValidator do
  @moduledoc false

  alias Ecto.Changeset
  alias ExJsonSchema.Schema
  alias ExJsonSchema.Validator
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError
  alias NetworkDefense.Evaluation.SchemaDiagnostics

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
  @snapshot_schema Schema.resolve(@snapshot_document)

  # The stored payload has no metadata wrapper. Its schema is the documented
  # payload definition, resolved as its own draft-04 document.
  @payload_schema Schema.resolve(%{
                    "$ref" => "#/definitions/payload",
                    "definitions" => Map.fetch!(@snapshot_document, "definitions")
                  })

  @request_schema @request_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @candidate_request_schema @candidate_request_path
                            |> File.read!()
                            |> Jason.decode!()
                            |> Schema.resolve()
  @candidate_response_schema @candidate_response_path
                             |> File.read!()
                             |> Jason.decode!()
                             |> Schema.resolve()
  @result_schema @result_path |> File.read!() |> Jason.decode!() |> Schema.resolve()
  @error_schema @error_path |> File.read!() |> Jason.decode!() |> Schema.resolve()

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
    case Validator.validate(schema(kind), value, error_formatter: false) do
      :ok -> :ok
      {:error, errors} when is_list(errors) -> {:error, schema_error(errors)}
      {:error, _reason} -> {:error, safe_error(kind)}
    end
  rescue
    _exception -> {:error, safe_error(kind)}
  end

  def matches_schema(%Changeset{} = changeset, raw, kind) do
    case validate(kind, raw) do
      :ok ->
        changeset

      {:error, error} ->
        Changeset.add_error(changeset, :base, "schema validation failed", pilot_error: error)
    end
  end

  def error_from_changeset(%Changeset{errors: errors}, fallback) do
    Enum.find_value(errors, fallback, fn
      {_field, {_message, options}} -> options[:pilot_error]
      _error -> nil
    end)
  end

  defp schema(:snapshot), do: @snapshot_schema
  defp schema(:snapshot_payload), do: @payload_schema
  defp schema(:request), do: @request_schema
  defp schema(:candidate_request), do: @candidate_request_schema
  defp schema(:candidate_response), do: @candidate_response_schema
  defp schema(:result), do: @result_schema
  defp schema(:error), do: @error_schema

  defp schema_error(errors) do
    case SchemaDiagnostics.build(errors) do
      [] -> generic_schema_error("Contract validation failed safely.")
      diagnostics -> PilotError.schema_failure(diagnostics)
    end
  end

  defp generic_schema_error(message) do
    PilotError.schema_failure([
      %{"message" => message, "path" => "#", "causes" => []}
    ])
  end

  defp safe_error(:snapshot),
    do: generic_schema_error("Evidence snapshot validation failed safely.")

  defp safe_error(:snapshot_payload),
    do: generic_schema_error("Stored evidence payload validation failed safely.")

  defp safe_error(:request),
    do: generic_schema_error("Pilot request validation failed safely.")

  defp safe_error(_kind), do: PilotError.invalid_response_contract()
end
