defmodule NetworkDefenseWeb.Contracts.Dashboard.ExecutionProgressEvent do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :correlation_id, :string
    field :graph_id, :string
    field :graph_revision_id, :string
    field :completed, :integer
    field :total, :integer
    field :detail, :string
  end

  @type t :: %__MODULE__{
          correlation_id: String.t(),
          graph_id: String.t(),
          graph_revision_id: String.t(),
          completed: integer(),
          total: integer(),
          detail: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:correlation_id, :graph_id, :graph_revision_id, :completed, :total, :detail])
    |> validate_required([:correlation_id, :graph_id, :graph_revision_id, :completed, :total])
    |> validate_number(:completed, greater_than_or_equal_to: 0)
    |> validate_number(:total, greater_than: 0)
  end
end
