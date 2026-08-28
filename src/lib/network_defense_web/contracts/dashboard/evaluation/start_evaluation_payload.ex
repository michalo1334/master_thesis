defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StartEvaluationPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :manifest_id, :string
  end

  @type t :: %__MODULE__{
          manifest_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:manifest_id])
    |> validate_required([:manifest_id])
    |> validate_length(:manifest_id, min: 1, max: 255)
  end
end
