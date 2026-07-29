defmodule NetworkDefense.Cvss do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  @attack_vector_weights %{network: 0.85, adjacent: 0.62, local: 0.55, physical: 0.2}
  @attack_complexity_weights %{low: 0.77, high: 0.44}
  @privileges_required_weights %{
    unchanged: %{none: 0.85, low: 0.62, high: 0.27},
    changed: %{none: 0.85, low: 0.68, high: 0.5}
  }
  @user_interaction_weights %{none: 0.85, required: 0.62}
  @impact_weights %{none: 0.0, low: 0.22, high: 0.56}

  embedded_schema do
    field :attack_vector, Ecto.Enum, values: Map.keys(@attack_vector_weights)
    field :attack_complexity, Ecto.Enum, values: Map.keys(@attack_complexity_weights)
    field :privileges_required, Ecto.Enum, values: [:none, :low, :high]
    field :user_interaction, Ecto.Enum, values: Map.keys(@user_interaction_weights)
    field :scope, Ecto.Enum, values: [:unchanged, :changed]
    field :confidentiality_impact, Ecto.Enum, values: Map.keys(@impact_weights)
    field :integrity_impact, Ecto.Enum, values: Map.keys(@impact_weights)
    field :availability_impact, Ecto.Enum, values: Map.keys(@impact_weights)
  end

  @type t :: %__MODULE__{}

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
  end

  @doc """
  Calculates the CVSS v3.1 base score from the stored base metrics.
  """
  @spec base_score(t()) :: float()
  def base_score(%__MODULE__{} = cvss) do
    impact_subscore = impact_subscore(cvss)

    if impact_subscore <= 0 do
      0.0
    else
      impact = impact(impact_subscore, cvss.scope)

      exploitability =
        8.22 *
          Map.fetch!(@attack_vector_weights, cvss.attack_vector) *
          Map.fetch!(@attack_complexity_weights, cvss.attack_complexity) *
          privileges_required_weight(cvss) *
          Map.fetch!(@user_interaction_weights, cvss.user_interaction)

      score =
        case cvss.scope do
          :unchanged -> min(impact + exploitability, 10.0)
          :changed -> min(1.08 * (impact + exploitability), 10.0)
        end

      round_up(score)
    end
  end

  defp impact_subscore(cvss) do
    1 -
      (1 - Map.fetch!(@impact_weights, cvss.confidentiality_impact)) *
        (1 - Map.fetch!(@impact_weights, cvss.integrity_impact)) *
        (1 - Map.fetch!(@impact_weights, cvss.availability_impact))
  end

  defp impact(impact_subscore, :unchanged), do: 6.42 * impact_subscore

  defp impact(impact_subscore, :changed) do
    7.52 * (impact_subscore - 0.029) - 3.25 * :math.pow(impact_subscore - 0.02, 15)
  end

  defp privileges_required_weight(cvss) do
    @privileges_required_weights
    |> Map.fetch!(cvss.scope)
    |> Map.fetch!(cvss.privileges_required)
  end

  # CVSS defines roundup as always rounding up to one decimal place.
  defp round_up(score), do: Float.ceil(score * 10 - 1.0e-5) / 10
end
