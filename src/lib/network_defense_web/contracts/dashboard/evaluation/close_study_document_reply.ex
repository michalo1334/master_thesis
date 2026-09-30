defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.CloseStudyDocumentReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  @enum_values status: [:closed, :not_found, :invalid_request]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
  end

  @type t :: %__MODULE__{status: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["closed", "not_found", "invalid_request"])
  end
end
