defmodule NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection.Issue do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  @issue_codes ~w(
    host_without_segment
    host_multiple_segments
    service_without_host
    service_multiple_hosts
    context_without_anchor
  )

  @severities ~w(info warning)

  @enum_values code: @issue_codes, severity: @severities

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :code, :string
    field :severity, :string
    field :entity_id, :string
    field :related_ids, {:array, :string}, default: []
  end

  @type t :: %__MODULE__{
          code: String.t(),
          severity: String.t(),
          entity_id: String.t(),
          related_ids: [String.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:code, :severity, :entity_id, :related_ids])
    |> validate_required([:code, :severity, :entity_id])
    |> Contracts.validate_uuid(:entity_id)
    |> validate_inclusion(:code, @issue_codes)
    |> validate_inclusion(:severity, @severities)
    |> validate_change(:related_ids, fn :related_ids, related_ids ->
      if Enum.all?(related_ids, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
        []
      else
        [related_ids: "contains an invalid UUID"]
      end
    end)
  end
end
