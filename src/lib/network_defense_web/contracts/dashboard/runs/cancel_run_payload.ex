defmodule NetworkDefenseWeb.Contracts.Dashboard.Runs.CancelRunPayload do
  @moduledoc false

  use NetworkDefenseWeb.Contracts, category: :runs

  embedded_schema do
    field :kind, :string
    field :run_id, :string
  end

  @type t :: %__MODULE__{kind: String.t(), run_id: String.t()}

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [:kind, :run_id])
    |> validate_required([:kind, :run_id])
    |> validate_inclusion(:kind, ["simulation", "optimization", "evaluation"])
    |> NetworkDefense.Contracts.validate_uuid(:run_id)
  end
end
