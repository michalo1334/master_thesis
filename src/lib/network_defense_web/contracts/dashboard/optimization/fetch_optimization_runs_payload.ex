defmodule NetworkDefenseWeb.Contracts.Dashboard.Optimization.FetchOptimizationRunsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  embedded_schema do
    field :graph_revision_ids, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          graph_revision_ids: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:graph_revision_ids])
    |> validate_change(:graph_revision_ids, fn :graph_revision_ids, revision_ids ->
      if Enum.all?(revision_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [graph_revision_ids: "contains an invalid UUID"]
      end
    end)
  end
end
