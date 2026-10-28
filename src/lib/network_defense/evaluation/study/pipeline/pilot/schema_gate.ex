defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.SchemaGate do
  @moduledoc false

  # Shared JSON Schema gate for one Pilot trust boundary.
  #
  # A boundary declares the schemas it validates and the safe error of every
  # kind. The gate owns the delegate bodies, so all Pilot boundaries validate
  # and report diagnostics the same way.
  #
  # Options:
  #
  #   * `:schemas` — keyword list of `kind => {file, :document | :payload}`.
  #
  # The using module must declare `@type kind` and implement `safe_error/1`.
  @callback safe_error(atom()) :: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error.t()

  defmacro __using__(options) do
    schemas = Keyword.fetch!(options, :schemas)

    quote bind_quoted: [schemas: schemas] do
      @behaviour NetworkDefense.Evaluation.Study.Pipeline.Pilot.SchemaGate

      alias Ecto.Changeset
      alias NetworkDefense.Evaluation.SchemaValidation
      alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Error, as: PilotError

      @gate_dir Application.app_dir(:network_defense, "priv/evaluation/pilot/v1/schemas")

      @schemas (for {kind, {file, resolution}} <- schemas, into: %{} do
                  path = Path.join(@gate_dir, file)
                  @external_resource path
                  document = path |> File.read!() |> Jason.decode!()

                  resolved =
                    case resolution do
                      :document -> SchemaValidation.resolve_document(document)
                      :payload -> SchemaValidation.resolve_payload(document)
                    end

                  {kind, resolved}
                end)

      @spec validate(kind(), term()) :: :ok | {:error, PilotError.t()}
      def validate(kind, value) do
        SchemaValidation.validate(
          value,
          fn -> Map.fetch!(@schemas, kind) end,
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

      defp generic_schema_error(message) do
        SchemaValidation.generic_schema_error(message, &PilotError.schema_failure/1)
      end
    end
  end
end
