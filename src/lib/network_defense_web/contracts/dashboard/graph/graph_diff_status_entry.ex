defmodule NetworkDefenseWeb.Web.Contracts.GraphDiffStatusEntry do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @enum_values status: [:added, :removed, :unchanged]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :id, :string
    field :status, :string
  end

  @type t :: %__MODULE__{id: String.t(), status: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :status])
    |> validate_required([:id, :status])
    |> Contracts.validate_uuid(:id)
    |> validate_inclusion(:status, ["added", "removed", "unchanged"])
  end
end
