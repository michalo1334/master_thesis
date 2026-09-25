defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjectionSegment do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :id, :string
    field :host_ids, {:array, :string}, default: []
    field :host_count, :integer
    field :service_count, :integer
    field :context_count, :integer
  end

  @type t :: %__MODULE__{
          id: String.t(),
          host_ids: [String.t()],
          host_count: non_neg_integer(),
          service_count: non_neg_integer(),
          context_count: non_neg_integer()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:id, :host_ids, :host_count, :service_count, :context_count])
    |> validate_required([:id, :host_count, :service_count, :context_count])
    |> Contracts.validate_uuid(:id)
    |> validate_change(:host_ids, fn :host_ids, host_ids ->
      if Enum.all?(host_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [host_ids: "contains an invalid UUID"]
      end
    end)
    |> validate_number(:host_count, greater_than_or_equal_to: 0)
    |> validate_number(:service_count, greater_than_or_equal_to: 0)
    |> validate_number(:context_count, greater_than_or_equal_to: 0)
  end
end
