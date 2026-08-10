defmodule NetworkDefenseWeb.Web.Contracts.OptimizationRunSummary do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :graph_title, :string
    field :strategy, :string
    field :objective, :string
    field :requested_budget, :integer
    field :used_budget, :integer
    field :runtime_ms, :integer
    field :output_graph_revision_id, :string
    field :started_at, :string
  end

  @type t :: %__MODULE__{
          id: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          graph_title: String.t(),
          strategy: String.t(),
          objective: String.t(),
          requested_budget: integer(),
          used_budget: integer(),
          runtime_ms: integer(),
          output_graph_revision_id: String.t(),
          started_at: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :id,
      :graph_id,
      :graph_revision_id,
      :graph_title,
      :strategy,
      :objective,
      :requested_budget,
      :used_budget,
      :runtime_ms,
      :output_graph_revision_id,
      :started_at
    ])
    |> validate_required([
      :id,
      :graph_id,
      :graph_revision_id,
      :graph_title,
      :strategy,
      :objective,
      :requested_budget,
      :used_budget,
      :runtime_ms,
      :output_graph_revision_id,
      :started_at
    ])
  end
end
