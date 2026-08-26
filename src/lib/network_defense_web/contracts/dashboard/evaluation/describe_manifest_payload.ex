defmodule NetworkDefenseWeb.Web.Contracts.DescribeManifestPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :content, :map
  end

  @type t :: %__MODULE__{
          content: map()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:content])
    |> validate_required([:content])
  end
end
