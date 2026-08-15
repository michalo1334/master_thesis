defmodule NetworkDefenseWeb.Web.Contracts.RunWorkflowPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :workflow

  alias NetworkDefenseWeb.Web.Contracts.RunWorkflowRequest

  embedded_schema do
    embeds_one :request, RunWorkflowRequest, on_replace: :update
  end

  @type t :: %__MODULE__{request: RunWorkflowRequest.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:request, required: true)
  end
end
