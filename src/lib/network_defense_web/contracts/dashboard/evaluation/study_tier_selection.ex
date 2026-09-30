defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyTierSelection do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :tier, :string
    field :run_id, :string
  end

  @type t :: %__MODULE__{tier: String.t(), run_id: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:tier, :run_id])
    |> validate_required([:tier, :run_id])
    |> validate_length(:tier, min: 1, max: 255)
    |> Contracts.validate_uuid(:run_id)
  end
end
