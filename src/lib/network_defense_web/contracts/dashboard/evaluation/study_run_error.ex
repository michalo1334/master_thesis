defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyRunError do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  @codes [
    :invalid_request,
    :invalid_specification,
    :specification_not_found,
    :invalid_tier_selection,
    :unsafe_tier_label,
    :duplicate_tier_label,
    :duplicate_run_id,
    :run_overlap,
    :invalid_run_id,
    :no_tiers,
    :run_not_found,
    :run_incomplete,
    :run_not_exportable,
    :run_warmup,
    :run_incompatible,
    :tier_declaration_mismatch,
    :tier_archive_too_large,
    :input_too_large,
    :output_too_large,
    :result_too_large,
    :invalid_mode,
    :final_not_available,
    :already_running,
    :document_locked,
    :document_not_found,
    :not_configured,
    :transport,
    :http_status,
    :content_type,
    :response_too_large,
    :invalid_body,
    :invalid_result,
    :cancelled,
    :internal_error
  ]

  @enum_values code: @codes
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :code, :string
  end

  @type t :: %__MODULE__{code: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:code])
    |> validate_required([:code])
    |> validate_inclusion(:code, Enum.map(@codes, &Atom.to_string/1))
  end
end
