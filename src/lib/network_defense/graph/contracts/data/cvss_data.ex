defmodule NetworkDefense.Graph.Contracts.Data.CvssData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  @enum_values [
    attack_vector: ~w(network adjacent local physical),
    attack_complexity: ~w(low high),
    privileges_required: ~w(none low high),
    user_interaction: ~w(none required),
    scope: ~w(unchanged changed),
    confidentiality_impact: ~w(none low high),
    integrity_impact: ~w(none low high),
    availability_impact: ~w(none low high)
  ]

  def contract_meta, do: %{enum_values: @enum_values}

  embedded_schema do
    field :attack_vector, :string
    field :attack_complexity, :string
    field :privileges_required, :string
    field :user_interaction, :string
    field :scope, :string
    field :confidentiality_impact, :string
    field :integrity_impact, :string
    field :availability_impact, :string
  end

  @type t :: %__MODULE__{
          attack_vector: String.t(),
          attack_complexity: String.t(),
          privileges_required: String.t(),
          user_interaction: String.t(),
          scope: String.t(),
          confidentiality_impact: String.t(),
          integrity_impact: String.t(),
          availability_impact: String.t()
        }

  def changeset(schema, attrs) do
    schema
    |> cast(attrs, [
      :attack_vector,
      :attack_complexity,
      :privileges_required,
      :user_interaction,
      :scope,
      :confidentiality_impact,
      :integrity_impact,
      :availability_impact
    ])
    |> validate_required([
      :attack_vector,
      :attack_complexity,
      :privileges_required,
      :user_interaction,
      :scope,
      :confidentiality_impact,
      :integrity_impact,
      :availability_impact
    ])
    |> validate_inclusion(:attack_vector, @enum_values[:attack_vector])
    |> validate_inclusion(:attack_complexity, @enum_values[:attack_complexity])
    |> validate_inclusion(:privileges_required, @enum_values[:privileges_required])
    |> validate_inclusion(:user_interaction, @enum_values[:user_interaction])
    |> validate_inclusion(:scope, @enum_values[:scope])
    |> validate_inclusion(:confidentiality_impact, @enum_values[:confidentiality_impact])
    |> validate_inclusion(:integrity_impact, @enum_values[:integrity_impact])
    |> validate_inclusion(:availability_impact, @enum_values[:availability_impact])
  end
end
