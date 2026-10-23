defmodule NetworkDefense.Graph.SharedValidationTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Contracts.Data.{
    MissionCapabilityData,
    NetworkSegmentData,
    VulnerabilityData
  }

  alias NetworkDefense.Graph.Data
  alias NetworkDefense.Nodes.{MissionCapability, NetworkSegment, Vulnerability}

  test "GRAPH-DATA-01: applies the same vulnerability validation to both model types" do
    attrs = %{
      "identifier" => "CVE-1",
      "exploit_probability" => 0.5,
      "cvss" => cvss()
    }

    assert Data.vulnerability_changeset(%Vulnerability{}, attrs).valid?
    assert Data.vulnerability_changeset(%VulnerabilityData{}, attrs).valid?

    for schema <- [%Vulnerability{}, %VulnerabilityData{}] do
      errors =
        schema |> Data.vulnerability_changeset(%{"exploit_probability" => 2}) |> errors_on()

      assert errors.identifier == ["can't be blank"]
      assert errors.cvss == ["can't be blank"]
      assert errors.exploit_probability == ["must be less than or equal to 1"]
    end
  end

  test "GRAPH-DATA-02: applies the same segment validation to both model types" do
    for schema <- [%NetworkSegment{}, %NetworkSegmentData{}] do
      assert Data.network_segment_changeset(schema, %{"name" => "DMZ", "cidr" => "10.0.0.0/24"}).valid?

      errors =
        schema
        |> Data.network_segment_changeset(%{"name" => "DMZ", "cidr" => "10.0.0.0/40"})
        |> errors_on()

      assert errors.cidr == ["must be a valid CIDR"]
    end
  end

  test "GRAPH-DATA-03: applies the same capability validation to both model types" do
    attrs = %{
      "name" => "Orders",
      "impact_weight" => 2.0,
      "min_operational_support" => 1,
      "required_flows" => []
    }

    assert Data.mission_capability_changeset(%MissionCapability{}, attrs).valid?
    assert Data.mission_capability_changeset(%MissionCapabilityData{}, attrs).valid?

    for schema <- [%MissionCapability{}, %MissionCapabilityData{}] do
      errors =
        schema
        |> Data.mission_capability_changeset(%{
          "name" => "Orders",
          "impact_weight" => 0,
          "min_operational_support" => 0
        })
        |> errors_on()

      assert errors.impact_weight == ["must be greater than 0"]
      assert errors.min_operational_support == ["must be greater than 0"]
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "none",
      "integrity_impact" => "none",
      "availability_impact" => "none"
    }
  end
end
