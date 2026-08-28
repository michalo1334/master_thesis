defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ManifestError do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :path, :string
    field :message, :string
  end

  @type t :: %__MODULE__{
          path: String.t(),
          message: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:path, :message])
    |> validate_required([:path, :message])
  end
end
