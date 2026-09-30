defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.GetStudySpecificationPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :id, :string
  end

  @type t :: %__MODULE__{id: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id])
    |> validate_required([:id])
    |> Contracts.validate_uuid(:id)
  end
end
