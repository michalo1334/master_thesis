defmodule NetworkDefense.Evaluation.ErrorContract do
  @moduledoc false

  # Declare the shared envelope in each owner. Study keeps its guarded
  # constructors local and does not expose the other owners' parsing APIs.
  defmacro __using__(options) do
    validator = Keyword.get(options, :schema_validator)
    request_size = Keyword.get(options, :request_size)
    correction_errors? = Keyword.get(options, :correction_errors, false)
    identifier_errors? = Keyword.get(options, :identifier_errors, false)

    quote do
      use NetworkDefense.Contracts, export: false

      alias NetworkDefense.Evaluation.ErrorEnvelope

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

      def new(code, issue_code, path, message, details \\ %{}),
        do: ErrorEnvelope.new(__MODULE__, code, issue_code, path, message, details)

      unquote(
        if validator do
          quote do
            def schema_failure(diagnostics),
              do: %__MODULE__{code: "validation_failed", schema_errors: diagnostics}

            def invalid_json_value(path),
              do:
                new(
                  "validation_failed",
                  "invalid_type",
                  path,
                  "The request contains a value that is not valid JSON."
                )

            def parse_envelope(value),
              do: ErrorEnvelope.parse(__MODULE__, value, &unquote(validator).validate(:error, &1))

            def materialize_envelope(value), do: ErrorEnvelope.materialize(__MODULE__, value)
          end
        end
      )

      unquote(
        case request_size do
          :limit_only ->
            quote do
              def request_too_large(limit_bytes),
                do:
                  new(
                    "request_too_large",
                    "request_too_large",
                    [],
                    "The request exceeds the byte limit.",
                    ErrorEnvelope.request_size_details(limit_bytes)
                  )
            end

          :with_actual ->
            quote do
              def request_too_large(limit_bytes, actual_bytes \\ nil),
                do:
                  new(
                    "request_too_large",
                    "request_too_large",
                    [],
                    "The request exceeds the byte limit.",
                    ErrorEnvelope.request_size_details(limit_bytes, actual_bytes)
                  )
            end

          nil ->
            nil
        end
      )

      unquote(
        if identifier_errors? do
          quote do
            def invalid_identifier(path),
              do:
                new(
                  "validation_failed",
                  "invalid_identifier",
                  path,
                  "The value must be a canonical UUID."
                )
          end
        end
      )

      unquote(
        if correction_errors? do
          quote do
            def invalid_correction(message \\ "The correction request or response is invalid.")
                when is_binary(message),
                do: new("invalid_response_contract", "invalid_correction", [], message)

            def invalid_correction_issues(issues) when is_list(issues) and issues != [],
              do: %__MODULE__{code: "invalid_response_contract", issues: issues}
          end
        end
      )
    end
  end
end
