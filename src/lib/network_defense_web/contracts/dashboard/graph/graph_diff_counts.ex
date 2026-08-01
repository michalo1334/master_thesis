defmodule NetworkDefenseWeb.Web.Contracts.GraphDiffCounts do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :added, :integer
    field :removed, :integer
    field :unchanged, :integer
  end

  @type t :: %__MODULE__{
          added: non_neg_integer(),
          removed: non_neg_integer(),
          unchanged: non_neg_integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:added, :removed, :unchanged])
    |> validate_required([:added, :removed, :unchanged])
    |> validate_number(:added, greater_than_or_equal_to: 0)
    |> validate_number(:removed, greater_than_or_equal_to: 0)
    |> validate_number(:unchanged, greater_than_or_equal_to: 0)
  end
end
