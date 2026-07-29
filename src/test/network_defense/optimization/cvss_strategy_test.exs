defmodule NetworkDefense.Optimization.CvssStrategyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.DefenseActions.PatchVulnerability
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Service, Vulnerability}
  alias NetworkDefense.Optimization.{CvssStrategy, Strategy}
  alias NetworkDefense.Relationships.HasVulnerability

  test "ranks vulnerability patches by CVSS score and then edge ID" do
    service =
      GraphFixtures.node("service", Service, %{
        "name" => "svc",
        "protocol" => "tcp",
        "port" => 443
      })

    high = GraphFixtures.node("high", Vulnerability, vulnerability_data(high_cvss()))
    low = GraphFixtures.node("low", Vulnerability, vulnerability_data(low_cvss()))

    graph =
      GraphFixtures.graph([service, high, low], [
        GraphFixtures.edge("b-low", service, low, HasVulnerability, privileges()),
        GraphFixtures.edge("a-high", service, high, HasVulnerability, privileges())
      ])

    assert [%PatchVulnerability{edge_id: "a-high"}, %PatchVulnerability{edge_id: "b-low"}] =
             Strategy.rank(%CvssStrategy{}, [PatchVulnerability], graph, 1)
  end

  test "does not return patches when patching is not enabled" do
    assert Strategy.rank(%CvssStrategy{}, [], GraphFixtures.graph([], []), 1) == []
  end

  defp vulnerability_data(cvss),
    do: %{"identifier" => "CVE", "cvss" => cvss, "exploit_probability" => 0.5}

  defp privileges, do: %{"required_privilege" => "none", "granted_privilege" => "user"}

  defp high_cvss do
    %{
      "attack_vector" => "network",
      "attack_complexity" => "low",
      "privileges_required" => "none",
      "user_interaction" => "none",
      "scope" => "unchanged",
      "confidentiality_impact" => "high",
      "integrity_impact" => "high",
      "availability_impact" => "high"
    }
  end

  defp low_cvss do
    %{
      "attack_vector" => "physical",
      "attack_complexity" => "high",
      "privileges_required" => "high",
      "user_interaction" => "required",
      "scope" => "unchanged",
      "confidentiality_impact" => "low",
      "integrity_impact" => "none",
      "availability_impact" => "none"
    }
  end
end
