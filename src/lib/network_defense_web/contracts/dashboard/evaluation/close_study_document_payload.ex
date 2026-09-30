defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.CloseStudyDocumentPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :document_id, :string
  end

  @type t :: %__MODULE__{document_id: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:document_id])
    |> validate_required([:document_id])
    |> Contracts.validate_uuid(:document_id)
  end
end
