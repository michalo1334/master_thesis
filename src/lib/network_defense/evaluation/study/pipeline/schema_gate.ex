defmodule NetworkDefense.Evaluation.Study.Pipeline.SchemaGate do
  @moduledoc false

  # Shared JSON Schema gate for one pipeline trust boundary.
  #
  # A boundary declares the schema directory it reads, the error module it
  # reports, the boundary tag that `SchemaValidation` records, and the safe error
  # of every kind. The gate owns the delegate bodies, so every boundary validates
  # serialized data and reports diagnostics the same way.
  #
  # Options:
  #
  #   * `:dir` — schema directory below the application `priv` directory.
  #   * `:error` — the owning error module, aliased as `Error`.
  #   * `:tag` — the boundary tag passed to `SchemaValidation`.
  #   * `:schemas` — keyword list of `kind => {file, :document | :payload}`.
  #
  # The using module declares `@type kind` and implements `safe_error/1`.
  @callback safe_error(atom()) :: term()

  defmacro __using__(options) do
    dir = Keyword.fetch!(options, :dir)
    error = Keyword.fetch!(options, :error)
    tag = Keyword.fetch!(options, :tag)
    schemas = Keyword.fetch!(options, :schemas)

    quote do
      @behaviour NetworkDefense.Evaluation.Study.Pipeline.SchemaGate

      alias Ecto.Changeset
      alias NetworkDefense.Evaluation.SchemaValidation
      alias unquote(error), as: Error

      @gate_dir Application.app_dir(:network_defense, unquote(dir))

      @schemas (for {kind, {file, resolution}} <- unquote(Macro.escape(schemas)), into: %{} do
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

      @spec validate(kind(), term()) :: :ok | {:error, Error.t()}
      def validate(kind, value) do
        SchemaValidation.validate(
          value,
          fn -> Map.fetch!(@schemas, kind) end,
          &Error.schema_failure/1,
          fn -> safe_error(kind) end
        )
      end

      def matches_schema(%Changeset{} = changeset, raw, kind) do
        SchemaValidation.matches_schema(changeset, raw, kind, &validate/2, unquote(tag))
      end

      def error_from_changeset(%Changeset{} = changeset, fallback) do
        SchemaValidation.error_from_changeset(changeset, fallback, unquote(tag))
      end

      defp generic_schema_error(message) do
        SchemaValidation.generic_schema_error(message, &Error.schema_failure/1)
      end
    end
  end
end
