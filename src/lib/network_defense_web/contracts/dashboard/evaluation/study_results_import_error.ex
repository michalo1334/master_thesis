defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyResultsImportError do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  @enum_values code: [:malformed_payload, :file_too_large, :invalid_archive, :unsupported_archive]
  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :code, :string
    field :message, :string
  end

  @type t :: %__MODULE__{code: String.t(), message: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:code, :message])
    |> validate_required([:code, :message])
    |> validate_inclusion(:code, [
      "malformed_payload",
      "file_too_large",
      "invalid_archive",
      "unsupported_archive"
    ])
  end
end
