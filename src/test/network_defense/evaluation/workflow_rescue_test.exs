defmodule NetworkDefense.Evaluation.WorkflowRescueTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Final.Binding
  alias NetworkDefense.Evaluation.Final.Contracts.FinalError
  alias NetworkDefense.Evaluation.Final.Workflow
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.{FinalCollectionWorkflow, GustWaiter, Resume}
  alias NetworkDefense.Evaluation.StudyPhase
  alias NetworkDefense.Repo

  @execution_id "00000000-0000-4000-8000-000000000001"

  # Inject failures at public dependencies. Do not stop repositories or change
  # database tables to simulate outages.
  for {id, boundary, operation, dependency, function, arity} <- [
        {"RESCUE-01", FinalCollectionWorkflow, :create, Repo, :get, 2},
        {"RESCUE-02", FinalCollectionWorkflow, :dispatch, Gust.Flows, :get_run!, 1},
        {"RESCUE-03", FinalCollectionWorkflow, :result, Gust.Flows, :get_tasks_by_name, 2},
        {"RESCUE-04", Workflow, :create, Binding, :verify, 2},
        {"RESCUE-05", Workflow, :dispatch, Gust.Flows, :get_run!, 1},
        {"RESCUE-06", Workflow, :await, GustWaiter, :await, 2},
        {"RESCUE-07", Workflow, :result, Gust.Repo, :get, 2},
        {"RESCUE-08", Workflow, :failure_for_run, Gust.Flows, :get_run_with_tasks!, 1},
        {"RESCUE-09", Resume, :resume, Repo, :transaction, 1}
      ] do
    @tag type: :unit
    test "#{id}: WHEN #{inspect(boundary)}.#{operation} encounters an exception, it SHALL propagate defects and bound only database failures" do
      boundary = unquote(boundary)
      operation = unquote(operation)
      dependency = unquote(dependency)
      function = unquote(function)
      arity = unquote(arity)
      args = arguments(boundary, operation)

      :meck.new(dependency, [:passthrough, :no_link])
      on_exit(fn -> :meck.unload(dependency) end)

      inject_exception(dependency, function, arity, %ArgumentError{message: "injected defect"})

      assert_raise ArgumentError, "injected defect", fn ->
        apply(boundary, operation, args)
      end

      for exception <- [
            %Postgrex.Error{message: "private database details"},
            %DBConnection.ConnectionError{message: "private connection details"}
          ] do
        inject_exception(dependency, function, arity, exception)
        assert apply(boundary, operation, args) == bounded_error(boundary, operation)
      end
    end
  end

  @tag type: :unit
  test "RESCUE-10: WHEN the waiter is unavailable, Final await SHALL keep its bounded unavailable error" do
    :meck.new(GustWaiter, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(GustWaiter) end)
    :meck.expect(GustWaiter, :await, fn 1, 0 -> {:error, :unavailable} end)

    assert Workflow.await(1, 0) == {:error, FinalError.unavailable()}

    assert FinalCollectionWorkflow.await(1, 0) ==
             {:error, StudyError.final_collection_workflow_failed()}
  end

  defp arguments(FinalCollectionWorkflow, :create),
    do: [%StudyPhase{execution_id: @execution_id}]

  defp arguments(Workflow, :create), do: [FinalConformance.request()]
  defp arguments(Workflow, :await), do: [1, 0]
  defp arguments(Resume, :resume), do: [@execution_id, :recommended]
  defp arguments(_boundary, _operation), do: [1]

  defp bounded_error(FinalCollectionWorkflow, _operation),
    do: {:error, StudyError.final_collection_workflow_failed()}

  defp bounded_error(Resume, :resume),
    do: {:error, StudyError.final_selection_storage_failed()}

  defp bounded_error(Workflow, :failure_for_run), do: FinalError.workflow_failed()
  defp bounded_error(Workflow, _operation), do: {:error, FinalError.workflow_failed()}

  defp inject_exception(module, function, 1, exception),
    do: :meck.expect(module, function, fn _argument -> raise exception end)

  defp inject_exception(module, function, 2, exception),
    do: :meck.expect(module, function, fn _first, _second -> raise exception end)
end
