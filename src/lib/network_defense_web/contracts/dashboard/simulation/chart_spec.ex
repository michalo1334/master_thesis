defmodule NetworkDefenseWeb.Web.Contracts.ChartSpec do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :dashboard

  embedded_schema do
    field :id, :string
    field :title, :string
    field :takeaway, :string
    field :aria_label, :string
    field :option, :map
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          takeaway: String.t(),
          aria_label: String.t(),
          option: map()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :title, :takeaway, :aria_label, :option])
    |> validate_required([:id, :title, :takeaway, :aria_label, :option])
  end
end
