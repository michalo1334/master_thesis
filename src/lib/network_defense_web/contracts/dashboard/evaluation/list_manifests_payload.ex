defmodule NetworkDefenseWeb.Contracts.Dashboard.Evaluation.ListManifestsPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :evaluation

  embedded_schema do
  end

  @type t :: %__MODULE__{}

  def changeset(schema, attrs), do: cast(schema, attrs, [])
end
