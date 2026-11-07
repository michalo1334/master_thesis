defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.TimingSummary do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :boundary, :string
    field :median_us, :integer
    field :minimum_us, :integer
    field :maximum_us, :integer
  end

  @type t :: %__MODULE__{
          boundary: String.t(),
          median_us: non_neg_integer(),
          minimum_us: non_neg_integer(),
          maximum_us: non_neg_integer()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
