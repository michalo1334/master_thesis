defmodule NetworkDefense.ContractsSharedValidationTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Contracts

  alias NetworkDefenseWeb.Contracts.Dashboard.Optimization.RunOptimizationReply
  alias NetworkDefenseWeb.Contracts.Dashboard.ReportRequestReply
  alias NetworkDefenseWeb.Contracts.Dashboard.Runs.CancelRunPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.FetchExperimentsPayload
  alias NetworkDefenseWeb.Contracts.Dashboard.Simulation.SimulationFailedEvent

  test "CONTRACT-VALIDATION-01: validates accepted and rejected run replies" do
    accepted =
      Contracts.run_reply_changeset(%RunOptimizationReply{}, %{
        "status" => "accepted",
        "error" => nil
      })

    assert accepted.valid?

    rejected =
      Contracts.run_reply_changeset(%RunOptimizationReply{}, %{"status" => "rejected"})

    assert errors_on(rejected).error == ["can't be blank"]
  end

  test "CONTRACT-VALIDATION-02: validates graph revision id lists" do
    assert Contracts.graph_revision_ids_changeset(%FetchExperimentsPayload{}, %{
             "graph_revision_ids" => [Ecto.UUID.generate()]
           }).valid?

    errors =
      %FetchExperimentsPayload{}
      |> Contracts.graph_revision_ids_changeset(%{"graph_revision_ids" => ["invalid"]})
      |> errors_on()

    assert errors.graph_revision_ids == ["contains an invalid UUID"]
  end

  test "CONTRACT-VALIDATION-03: validates report request statuses" do
    assert Contracts.report_request_changeset(%ReportRequestReply{}, %{
             "status" => "processing"
           }).valid?

    errors =
      %ReportRequestReply{}
      |> Contracts.report_request_changeset(%{"status" => "complete"})
      |> errors_on()

    assert errors.status == ["is invalid"]
  end

  test "CONTRACT-VALIDATION-04: validates run references" do
    assert Contracts.run_reference_changeset(%CancelRunPayload{}, %{
             "kind" => "simulation",
             "run_id" => Ecto.UUID.generate()
           }).valid?

    errors =
      %CancelRunPayload{}
      |> Contracts.run_reference_changeset(%{"kind" => "other", "run_id" => "invalid"})
      |> errors_on()

    assert errors.kind == ["is invalid"]
    assert errors.run_id == ["is invalid"]
  end

  test "CONTRACT-VALIDATION-05: requires failure identifiers and an embedded error" do
    errors =
      %SimulationFailedEvent{}
      |> Contracts.run_failure_changeset(%{})
      |> errors_on()

    assert errors.correlation_id == ["can't be blank"]
    assert errors.graph_id == ["can't be blank"]
    assert errors.graph_revision_id == ["can't be blank"]
    assert errors.error == ["can't be blank"]
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
