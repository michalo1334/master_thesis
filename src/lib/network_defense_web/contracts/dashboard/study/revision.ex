defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.Revision do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    field :study_id, :string
    field :revision, :integer
  end

  @type t :: %__MODULE__{
          study_id: String.t(),
          revision: pos_integer()
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
