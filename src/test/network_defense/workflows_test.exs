defmodule NetworkDefense.WorkflowsTest do
  use NetworkDefense.DataCase
  use Oban.Testing, repo: NetworkDefense.Repo

  import Ecto.Query

  alias NetworkDefense.Analysis.CombinedAnalysisWorkflow
  alias NetworkDefense.Graph.{Edge, Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, NetworkSegment}
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimization.Contracts.OptimizationParams
  alias NetworkDefense.Relationships.Contains
  alias NetworkDefense.Simulation.Contracts.SimulationParams
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Workflows
  alias NetworkDefense.Workflows.{AnalysisInputRevision, StepWorker, WorkflowRun, WorkflowStep}

  test "runs a generic two-step template linearly" do
    assert {:ok, run} = Workflows.start("two_step", %{})
    assert is_binary(run.title)
    assert [first_adjective, second_adjective, _noun] = String.split(run.title, " ")
    refute first_adjective == second_adjective

    assert :ok = perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 1})
    assert_receive {:workflow_template_prepare, "first", true}
    assert_receive {:workflow_template, "first"}

    assert_enqueued(
      worker: StepWorker,
      queue: :workflows,
      args: %{"workflow_run_id" => run.id, "step_position" => 2}
    )

    assert :ok = perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 2})

    assert %{status: "completed"} = Repo.get!(WorkflowRun, run.id)
    assert [{1, "completed"}, {2, "completed"}] = step_statuses(run.id)
  end

  test "retries a failed step without rerunning completed steps" do
    assert {:ok, run} = Workflows.start("two_step", %{"fail_second_once" => true})

    assert :ok = perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 1})
    assert_receive {:workflow_template, "first"}

    assert {:error, :transient_failure} =
             perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 2})

    assert_receive {:workflow_template_prepare, "second", true}
    assert [{1, "completed"}, {2, "pending"}] = step_statuses(run.id)
    assert %WorkflowStep{resource_id: "second-resource"} = step(run.id, 2)

    assert :ok = perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 2})
    refute_receive {:workflow_template_prepare, "second", _}
    refute_receive {:workflow_template, "first"}
    assert %{status: "completed"} = Repo.get!(WorkflowRun, run.id)
  end

  test "leaves a step pending when template preparation fails before the final retry" do
    assert {:ok, run} = Workflows.start("two_step", %{"fail_second_prepare" => true})

    assert :ok = perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 1})

    assert {:error, :prepare_failed} =
             perform_job(
               StepWorker,
               %{"workflow_run_id" => run.id, "step_position" => 2},
               attempt: 2
             )

    assert %{status: "pending", resource_id: nil} = step(run.id, 2)
  end

  test "combined analysis persists baseline, optimization, and post-optimization outputs" do
    assert {:ok, graph} = Graphs.insert(graph_with_host())
    host = Enum.find(Graph.nodes(graph), &(&1.type == Host))

    assert {:ok, run} =
             CombinedAnalysisWorkflow.start(
               graph.revision_id,
               "combined-analysis",
               %SimulationParams{
                 monte_carlo_trials: 1,
                 iterations_per_run: 1,
                 initial_foothold_node_id: host.id,
                 seed: 1,
                 generate_seed: false,
                 max_attempts: 1
               },
               %OptimizationParams{strategy: "cvss", objective: "blast_radius", budget: 1}
             )

    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Workflows.workflow_events_topic())

    for position <- 1..3 do
      assert :ok =
               perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => position})
    end

    assert %{status: "completed"} = Repo.get!(WorkflowRun, run.id)
    assert [baseline, optimization, post_optimization] = steps(run.id)
    assert baseline.output["experiment_id"]
    assert optimization.output["optimization_run_id"]
    assert optimization.output["output_graph_revision_id"] != graph.revision_id

    assert post_optimization.output["graph_revision_id"] ==
             optimization.output["output_graph_revision_id"]

    analysis_id = run.id
    assert [input_revision_id] = input_revision_ids(run.id)
    assert input_revision_id == graph.revision_id

    assert %{analysis_id: ^analysis_id} = Experiments.get(baseline.output["experiment_id"])

    assert %{analysis_id: ^analysis_id} =
             OptimizationRuns.load(optimization.output["optimization_run_id"])

    assert %{analysis_id: ^analysis_id} =
             Experiments.get(post_optimization.output["experiment_id"])

    assert %{analysisId: ^analysis_id} =
             Enum.find(
               Graphs.list_summaries(),
               &(&1.revisionId == optimization.output["output_graph_revision_id"])
             )

    assert_receive {:workflow_completed, %{workflow_id: workflow_id, outputs: outputs}}

    assert workflow_id == run.id

    assert outputs == %{
             "baseline_simulation" => baseline.output,
             "optimization" => optimization.output,
             "post_optimization_simulation" => post_optimization.output
           }
  end

  test "returns the existing combined analysis workflow for the same correlation" do
    assert {:ok, graph} = Graphs.insert(graph_with_host())
    host = Enum.find(Graph.nodes(graph), &(&1.type == Host))

    params = %SimulationParams{
      monte_carlo_trials: 1,
      iterations_per_run: 1,
      initial_foothold_node_id: host.id,
      seed: 1,
      generate_seed: false,
      max_attempts: 1
    }

    optimization = %OptimizationParams{strategy: "cvss", objective: "blast_radius", budget: 1}

    assert {:ok, first} =
             CombinedAnalysisWorkflow.start(
               graph.revision_id,
               "same-request",
               params,
               optimization
             )

    assert {:ok, second} =
             CombinedAnalysisWorkflow.start(
               graph.revision_id,
               "same-request",
               params,
               optimization
             )

    assert first.id == second.id
    assert [input_revision_id] = input_revision_ids(first.id)
    assert input_revision_id == graph.revision_id

    assert [job] = all_enqueued(worker: StepWorker)
    assert job.args == %{"workflow_run_id" => first.id, "step_position" => 1}
  end

  test "marks the workflow failed and broadcasts after the final retry" do
    assert {:ok, run} = Workflows.start("two_step", %{"fail_second_always" => true})
    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Workflows.workflow_events_topic())

    assert :ok = perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 1})

    assert {:error, :internal_error} =
             perform_job(
               StepWorker,
               %{"workflow_run_id" => run.id, "step_position" => 2},
               attempt: 3
             )

    assert %{status: "failed", error: ":internal_error"} = Repo.get!(WorkflowRun, run.id)
    assert %WorkflowStep{status: "failed", error: ":internal_error"} = step(run.id, 2)
    assert_receive {:workflow_failed, %{workflow_id: workflow_id, reason: :internal_error}}
    assert workflow_id == run.id
  end

  test "settles template exits and throws after the final retry" do
    Phoenix.PubSub.subscribe(NetworkDefense.PubSub, Workflows.workflow_events_topic())

    for {termination, reason} <- [
          {"exit", {:exit, :template_exit}},
          {"throw", {:throw, :template_throw}}
        ] do
      assert {:ok, run} = Workflows.start("two_step", %{"terminate_second" => termination})

      assert :ok = perform_job(StepWorker, %{"workflow_run_id" => run.id, "step_position" => 1})

      assert {:error, ^reason} =
               perform_job(
                 StepWorker,
                 %{"workflow_run_id" => run.id, "step_position" => 2},
                 attempt: 3
               )

      assert %{status: "failed", error: error} = Repo.get!(WorkflowRun, run.id)
      assert error == inspect(reason)
      assert %WorkflowStep{status: "failed", error: ^error} = step(run.id, 2)
      assert_receive {:workflow_failed, %{workflow_id: workflow_id, reason: ^reason}}
      assert workflow_id == run.id
    end
  end

  defp step_statuses(run_id), do: steps(run_id) |> Enum.map(&{&1.position, &1.status})

  defp step(run_id, position) do
    WorkflowStep
    |> where([step], step.workflow_run_id == ^run_id and step.position == ^position)
    |> Repo.one!()
  end

  defp steps(run_id) do
    WorkflowStep
    |> where([step], step.workflow_run_id == ^run_id)
    |> order_by([step], asc: step.position)
    |> Repo.all()
  end

  defp input_revision_ids(run_id) do
    AnalysisInputRevision
    |> where([input], input.workflow_run_id == ^run_id)
    |> select([input], input.graph_revision_id)
    |> Repo.all()
  end

  defp graph_with_host do
    graph = Graph.new("workflow")
    segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "segment"})
    host = GraphFixtures.build_node(graph, Host, %{"name" => "foothold"})

    graph
    |> Graph.add_node(segment)
    |> Graph.add_node(host)
    |> Graph.add_edge(
      Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}})
    )
  end
end
