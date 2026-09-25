defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjectionHost do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :id, :string
    field :segment_id, :string
    field :service_ids, {:array, :string}, default: []
    field :service_count, :integer
    field :context_count, :integer
  end

  @type t :: %__MODULE__{
          id: String.t(),
          segment_id: String.t() | nil,
          service_ids: [String.t()],
          service_count: non_neg_integer(),
          context_count: non_neg_integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :segment_id, :service_ids, :service_count, :context_count])
    |> validate_required([:id, :service_count, :context_count])
    |> Contracts.validate_uuid(:id)
    |> Contracts.validate_uuid(:segment_id)
    |> validate_change(:service_ids, fn :service_ids, service_ids ->
      if Enum.all?(service_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [service_ids: "contains an invalid UUID"]
      end
    end)
    |> validate_number(:service_count, greater_than_or_equal_to: 0)
    |> validate_number(:context_count, greater_than_or_equal_to: 0)
  end
end
