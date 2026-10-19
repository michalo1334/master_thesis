defmodule NetworkDefense.Evaluation.Family.Contracts.AdjustedMember do
  @moduledoc false
  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  @type t :: %__MODULE__{
          identity: Identity.t(),
          raw_p_value: float(),
          adjusted_p_value: float(),
          reject_null: boolean()
        }

  embedded_schema do
    embeds_one :identity, Identity, on_replace: :update
    field :raw_p_value, :float
    field :adjusted_p_value, :float
    field :reject_null, :boolean
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:raw_p_value, :adjusted_p_value, :reject_null])
    |> cast_embed(:identity, required: true)
  end
end
