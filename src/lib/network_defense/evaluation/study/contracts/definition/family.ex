defmodule NetworkDefense.Evaluation.Study.Contracts.Definition.Family do
  @moduledoc false

  use NetworkDefense.Contracts, export: false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.Comparison

  # The declared primary comparison family.
  #
  # The comparison order is the declared order, so the correction step receives
  # the same member positions in Pilot and in Final. The list is never sorted.

  @type t :: %__MODULE__{
          id: String.t(),
          method: String.t(),
          alpha: float(),
          comparisons: [Comparison.t()]
        }

  embedded_schema do
    field :id, :string
    field :method, :string
    field :alpha, :float
    embeds_many :comparisons, Comparison, on_replace: :delete
  end

  def changeset(family, attrs) do
    family
    |> change()
    |> cast(attrs, [:id, :method, :alpha])
    |> cast_embed(:comparisons, required: true)
    |> validate_required([:id, :method, :alpha])
    |> validate_number(:alpha, greater_than: 0, less_than: 1)
    |> validate_length(:comparisons, min: 1)
  end
end
