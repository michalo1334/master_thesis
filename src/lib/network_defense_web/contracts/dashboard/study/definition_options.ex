defmodule NetworkDefenseWeb.Contracts.Dashboard.Study.DefinitionOptions do
  @moduledoc false
  use NetworkDefenseWeb.Contracts, category: :study

  def contract_meta do
    %{
      enum_values: [
        rules: NetworkDefense.Rules.Registry.values(),
        actions: NetworkDefense.DefenseActions.Registry.values()
      ]
    }
  end

  embedded_schema do
    field :study_id, :string
    field :family_id, :string
    field :actions, {:array, :string}
    field :rules, {:array, :string}

    embeds_many :alternatives, NetworkDefenseWeb.Contracts.Dashboard.Study.StrategyOption,
      on_replace: :delete

    field :objectives, {:array, :string}
    field :measurement_label, :string
  end

  @type t :: %__MODULE__{
          study_id: String.t() | nil,
          family_id: String.t() | nil,
          actions: [String.t()],
          rules: [String.t()],
          alternatives: [NetworkDefenseWeb.Contracts.Dashboard.Study.StrategyOption.t()],
          objectives: [String.t()],
          measurement_label: String.t() | nil
        }

  def changeset(schema, attrs), do: NetworkDefenseWeb.StudyContract.changeset(schema, attrs)
end
