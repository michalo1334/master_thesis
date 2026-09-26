defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.FlowGroup do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  embedded_schema do
    field :source_host_id, :string
    field :target_host_id, :string
    field :service_ids, {:array, :string}, default: []
    field :flow_ids, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          source_host_id: String.t(),
          target_host_id: String.t(),
          service_ids: [String.t()],
          flow_ids: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:source_host_id, :target_host_id, :service_ids, :flow_ids])
    |> validate_required([:source_host_id, :target_host_id])
    |> Contracts.validate_uuid(:source_host_id)
    |> Contracts.validate_uuid(:target_host_id)
    |> validate_change(:service_ids, fn :service_ids, service_ids ->
      if Enum.all?(service_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [service_ids: "contains an invalid UUID"]
      end
    end)
    |> validate_change(:flow_ids, fn :flow_ids, flow_ids ->
      if Enum.all?(flow_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [flow_ids: "contains an invalid UUID"]
      end
    end)
  end
end
