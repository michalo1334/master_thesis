defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudySpecificationSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :id, :string
    field :study_id, :string
    field :specification_version, :integer
    field :title, :string
    field :content, :map
  end

  @type t :: %__MODULE__{
          id: String.t(),
          study_id: String.t(),
          specification_version: pos_integer(),
          title: String.t(),
          content: map() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :study_id, :specification_version, :title, :content])
    |> validate_required([:id, :study_id, :specification_version, :title])
    |> validate_number(:specification_version, greater_than: 0)
  end
end
