defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.FinalComparison do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  embedded_schema do
    embeds_one :identity, NetworkDefenseWeb.Contracts.Dashboard.Study.ComparisonIdentity,
      on_replace: :delete

    field :method, :string
    field :contrast, :string
    field :estimate, :float
    field :confidence_level, :float
    field :lower, :float
    field :upper, :float
    field :test_method, :string
    field :test_alternative, :string
    field :raw_p_value, :float
    field :adjusted_p_value, :float
    field :reject_null, :boolean
    field :assessment, :string
    field :warnings, {:array, :string}
  end

  @type t :: %__MODULE__{
          identity: NetworkDefenseWeb.Contracts.Dashboard.Study.ComparisonIdentity.t(),
          method: String.t(),
          contrast: String.t(),
          estimate: float(),
          confidence_level: float(),
          lower: float(),
          upper: float(),
          test_method: String.t(),
          test_alternative: String.t(),
          raw_p_value: float(),
          adjusted_p_value: float(),
          reject_null: boolean(),
          assessment: String.t(),
          warnings: [String.t()]
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
