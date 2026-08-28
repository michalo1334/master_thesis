defmodule NetworkDefenseWeb.Contracts.Dashboard.Optimization.OptimizationCompletedEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :output_graph_revision_id, :string
    field :optimization_id, :string
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          output_graph_revision_id: String.t(),
          optimization_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :correlation_id,
      :graph_id,
      :graph_revision_id,
      :output_graph_revision_id,
      :optimization_id
    ])
    |> validate_required([
      :correlation_id,
      :graph_id,
      :graph_revision_id,
      :output_graph_revision_id,
      :optimization_id
    ])
  end
end
