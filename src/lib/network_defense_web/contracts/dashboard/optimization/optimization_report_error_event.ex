defmodule NetworkDefenseWeb.Web.Contracts.OptimizationReportErrorEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :optimization_id, :string
    field :graph_revision_id, :string
    field :reason, :string
  end

  @type t :: %__MODULE__{
          optimization_id: String.t(),
          graph_revision_id: String.t(),
          reason: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:optimization_id, :graph_revision_id, :reason])
    |> validate_required([:optimization_id, :graph_revision_id, :reason])
  end
end
