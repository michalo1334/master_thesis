defmodule NetworkDefenseWeb.Web.Contracts.RunSimulationReply do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :simulation

  @enum_values status: [:accepted, :rejected]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :status, :string
    field :graph_id, :string
    field :correlation_id, :string
    field :reason, :string
  end

  @type t :: %__MODULE__{
          status: String.t(),
          graph_id: String.t(),
          correlation_id: String.t(),
          reason: String.t() | nil
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:status, :graph_id, :correlation_id, :reason], empty_values: [])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["accepted", "rejected"])
  end
end
