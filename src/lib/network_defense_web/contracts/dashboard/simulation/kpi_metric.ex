defmodule NetworkDefenseWeb.Web.Contracts.KpiMetric do
  @moduledoc false

  use NetworkDefenseWeb.Contracts

  embedded_schema do
    field :label, :string
    field :value, :string
    field :detail, :string
    field :tone, :string
  end

  @type t :: %__MODULE__{
          label: String.t(),
          value: String.t(),
          detail: String.t(),
          tone: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:label, :value, :detail, :tone])
    |> validate_required([:label, :value, :detail, :tone])
  end
end
