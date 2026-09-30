defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationDescription do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :study_id, :string
    field :specification_version, :integer
    field :tiers, {:array, :string}
  end

  @type t :: %__MODULE__{
          study_id: String.t(),
          specification_version: pos_integer(),
          tiers: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:study_id, :specification_version, :tiers])
    |> validate_required([:study_id, :specification_version, :tiers])
    |> validate_number(:specification_version, greater_than: 0)
  end
end
