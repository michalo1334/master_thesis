defmodule NetworkDefense.Graph.Contracts.Data.CvssData do
  @moduledoc false

  use NetworkDefense.Contracts, category: :graph

  @attack_vectors ~w(network adjacent local physical)
  @attack_complexities ~w(low high)
  @privileges_required ~w(none low high)
  @user_interactions ~w(none required)
  @scopes ~w(unchanged changed)
  @impact_values ~w(none low high)

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
    |> validate_inclusion(:attack_vector, @attack_vectors)
    |> validate_inclusion(:attack_complexity, @attack_complexities)
    |> validate_inclusion(:privileges_required, @privileges_required)
    |> validate_inclusion(:user_interaction, @user_interactions)
    |> validate_inclusion(:scope, @scopes)
    |> validate_inclusion(:confidentiality_impact, @impact_values)
    |> validate_inclusion(:integrity_impact, @impact_values)
    |> validate_inclusion(:availability_impact, @impact_values)
  end
end
