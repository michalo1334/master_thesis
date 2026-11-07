defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.RevisionContext do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :method, :string
    field :seed_contract, :string
    field :measurement_label, :string
  end

  @type t :: %__MODULE__{
          method: String.t(),
          seed_contract: String.t(),
          measurement_label: String.t() | nil
        }
  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
