defmodule NetworkDefense.Evaluation.Family.Contracts.RawResult do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  @type t :: %__MODULE__{identity: Identity.t(), raw_p_value: float()}

  embedded_schema do
    embeds_one :identity, Identity, on_replace: :update
    field :raw_p_value, :float
  end

  def changeset(raw_result, attrs) do
    raw_result
    |> cast(attrs, [:raw_p_value])
    |> cast_embed(:identity, required: true)
  end
end
