defmodule NetworkDefenseWeb.Web.Contracts.OptimizationProgressEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :completed_steps, :integer
    field :total_steps, :integer
    field :phase, :string
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          completed_steps: integer(),
          total_steps: integer(),
          phase: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :correlation_id,
      :graph_id,
      :graph_revision_id,
      :completed_steps,
      :total_steps,
      :phase
    ])
    |> validate_required([
      :correlation_id,
      :graph_id,
      :graph_revision_id,
      :completed_steps,
      :total_steps,
      :phase
    ])
    |> validate_number(:completed_steps, greater_than_or_equal_to: 0)
    |> validate_number(:total_steps, greater_than: 0)
  end
end
