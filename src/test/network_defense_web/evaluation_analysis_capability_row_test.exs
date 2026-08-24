defmodule NetworkDefenseWeb.EvaluationAnalysisCapabilityRowTest do
  use ExUnit.Case, async: true

  alias NetworkDefenseWeb.Web.Contracts.EvaluationAnalysisCapabilityRow

  test "casts an optional capability name" do
    assert EvaluationAnalysisCapabilityRow.changeset(%EvaluationAnalysisCapabilityRow{}, %{
             "capability_id" => "capability",
             "capability_name" => "Capability"
           }).valid?

    assert EvaluationAnalysisCapabilityRow.changeset(%EvaluationAnalysisCapabilityRow{}, %{
             "capability_id" => "capability"
           }).valid?
  end

  test "rejects a non-string capability name" do
    changeset =
      EvaluationAnalysisCapabilityRow.changeset(%EvaluationAnalysisCapabilityRow{}, %{
        "capability_name" => 1
      })

    refute changeset.valid?
    assert %{capability_name: ["is invalid"]} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
