defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.SaveStudySpecificationPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :title, :string
    field :content, :map
  end

  @type t :: %__MODULE__{
          title: String.t(),
          content: map()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:title, :content])
    |> validate_required([:title, :content])
    |> validate_length(:title, min: 1, max: 255)
  end
end
