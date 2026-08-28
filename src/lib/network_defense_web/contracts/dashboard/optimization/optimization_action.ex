defmodule NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationAction do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :id, :string
    field :label, :string
    field :kind, :string
    field :cvss_score, :float
    field :cost, :integer
  end

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          kind: String.t(),
          cvss_score: float() | nil,
          cost: integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :label, :kind, :cvss_score, :cost])
    |> validate_required([:id, :label, :kind, :cost])
  end
end
