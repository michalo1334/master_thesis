defmodule NetworkDefenseWeb.Web.Contracts.DashboardError do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefense.Errors

  @enum_values code: Errors.codes()
  @enum_type_aliases %{code: "ErrorCode"}

  def contract_meta,
    do: %{enum_values: @enum_values, enum_type_aliases: @enum_type_aliases}

  embedded_schema do
    field :code, :string
  end

  @type t :: %__MODULE__{code: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:code])
    |> validate_required([:code])
    |> validate_inclusion(:code, Errors.strings())
  end
end
