defmodule NetworkDefense.CvssTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Cvss

  test "calculates CVSS v3.1 base scores from base metrics" do
    assert Cvss.base_score(
             cvss(%{
               confidentiality_impact: :high,
               integrity_impact: :high,
               availability_impact: :high
             })
           ) ==
             9.8

    assert Cvss.base_score(
             cvss(%{
               scope: :changed,
               confidentiality_impact: :high,
               integrity_impact: :high,
               availability_impact: :high
             })
           ) ==
             10.0

    assert Cvss.base_score(
             cvss(%{
               attack_vector: :local,
               attack_complexity: :high,
               privileges_required: :high,
               user_interaction: :required
             })
           ) ==
             0.0
  end

  test "requires every base metric" do
    changeset = Cvss.changeset(%Cvss{}, %{attack_vector: "network"})

    refute changeset.valid?
  end

  defp cvss(overrides) do
    %Cvss{
      attack_vector: :network,
      attack_complexity: :low,
      privileges_required: :none,
      user_interaction: :none,
      scope: :unchanged,
      confidentiality_impact: :none,
      integrity_impact: :none,
      availability_impact: :none
    }
    |> Map.merge(overrides)
  end
end
