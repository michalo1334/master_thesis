defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ImportStudyResultsPayload do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
    field :archive, :string
  end

  @type t :: %__MODULE__{archive: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:archive])
    |> validate_required([:archive])
  end
end
