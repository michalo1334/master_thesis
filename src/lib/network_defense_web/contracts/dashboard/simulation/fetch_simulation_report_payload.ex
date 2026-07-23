defmodule NetworkDefenseWeb.Web.Contracts.FetchSimulationReportPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts

  embedded_schema do
    field :multi_state_id, :string
    field :graph_id, :string
  end

  @type t :: %__MODULE__{
          multi_state_id: String.t(),
          graph_id: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:multi_state_id, :graph_id])
    |> validate_required([:multi_state_id, :graph_id])
    |> validate_length(:multi_state_id, min: 1)
    |> validate_length(:graph_id, min: 1)
  end
end
