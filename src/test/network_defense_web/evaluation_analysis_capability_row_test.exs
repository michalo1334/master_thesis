defmodule NetworkDefenseWeb.EvaluationAnalysisCapabilityRowTest do
  use ExUnit.Case, async: true

  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.EvaluationAnalysisCapabilityRow

  test "casts an optional capability name" do
    assert EvaluationAnalysisCapabilityRow.changeset(
             %EvaluationAnalysisCapabilityRow{},
             required_fields(%{"capability_name" => "Capability"})
           ).valid?

    assert EvaluationAnalysisCapabilityRow.changeset(
             %EvaluationAnalysisCapabilityRow{},
             required_fields()
           ).valid?
  end

  test "requires the non-null capability row fields" do
    changeset =
      EvaluationAnalysisCapabilityRow.changeset(%EvaluationAnalysisCapabilityRow{}, %{
        "model_variant" => "full",
        "baseline_model_variant" => "full"
      })

    refute changeset.valid?

    assert %{
             capability_id: ["can't be blank"],
             comparison: ["can't be blank"],
             strategy: ["can't be blank"],
             baseline: ["can't be blank"],
             budget: ["can't be blank"]
           } = errors_on(changeset)
  end

  defp required_fields(overrides \\ %{}) do
    Map.merge(
      %{
        "comparison" => 0,
        "strategy" => "simulation_informed",
        "model_variant" => "full",
        "baseline" => "cvss",
        "baseline_model_variant" => "full",
        "budget" => 1,
        "capability_id" => "capability"
      },
      overrides
    )
  end

  test "requires tested and baseline model variants" do
    changeset =
      EvaluationAnalysisCapabilityRow.changeset(%EvaluationAnalysisCapabilityRow{}, %{
        "capability_id" => "capability"
      })

    refute changeset.valid?

    assert %{
             model_variant: ["can't be blank"],
             baseline_model_variant: ["can't be blank"]
           } = errors_on(changeset)
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
