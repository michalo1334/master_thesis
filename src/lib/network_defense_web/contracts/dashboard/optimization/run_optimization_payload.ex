defmodule NetworkDefenseWeb.Web.Contracts.RunOptimizationPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :optimization

  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest

  embedded_schema do
    embeds_one :request, RunOptimizationRequest, on_replace: :update
  end

  @type t :: %__MODULE__{request: RunOptimizationRequest.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [])
    |> cast_embed(:request, required: true)
  end
end
