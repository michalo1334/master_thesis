defmodule NetworkDefenseWeb.Contracts.Dashboard.Runs.CancelRunPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :runs

  embedded_schema do
    field :kind, :string
    field :run_id, :string
  end

  @type t :: %__MODULE__{kind: String.t(), run_id: String.t()}

  def changeset(schema, attrs), do: Contracts.run_reference_changeset(schema, attrs)
end
