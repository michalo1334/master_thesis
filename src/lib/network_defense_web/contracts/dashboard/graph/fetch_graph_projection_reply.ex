defmodule NetworkDefenseWeb.Web.Contracts.FetchGraphProjectionReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :graph

  alias NetworkDefenseWeb.Web.Contracts.{
    GraphProjectionHost,
    GraphProjectionOperationalFlow,
    GraphProjectionPolicyLink,
    GraphProjectionSegment
  }

  @enum_values status: [:ok, :not_found, :invalid_graph, :unmapped_error]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    embeds_many :segments, GraphProjectionSegment, on_replace: :delete
    embeds_many :hosts, GraphProjectionHost, on_replace: :delete
    embeds_many :policy_links, GraphProjectionPolicyLink, on_replace: :delete
    embeds_many :operational_flows, GraphProjectionOperationalFlow, on_replace: :delete
  end

  @type t :: %__MODULE__{
          status: String.t(),
          segments: [GraphProjectionSegment.t()],
          hosts: [GraphProjectionHost.t()],
          policy_links: [GraphProjectionPolicyLink.t()],
          operational_flows: [GraphProjectionOperationalFlow.t()]
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status])
    |> cast_embed(:segments)
    |> cast_embed(:hosts)
    |> cast_embed(:policy_links)
    |> cast_embed(:operational_flows)
    |> validate_required([:status])
    |> validate_inclusion(:status, ["ok", "not_found", "invalid_graph", "unmapped_error"])
  end
end
