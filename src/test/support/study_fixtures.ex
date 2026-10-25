defmodule NetworkDefense.Evaluation.StudyFixtures do
  @moduledoc false

  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase, StudyRevision}
  alias NetworkDefense.Graph.{Edge, Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, NetworkSegment}

  alias NetworkDefense.Optimization.Contracts.{
    OptimizationParams,
    RunOptimizationRequest,
    SimulationSettings
  }

  alias NetworkDefense.Relationships.Contains
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Contracts.{RunSimulationRequest, SimulationParams}

  # Stored study rows for repository tests.
  #
  # One revision holds one execution, and one execution holds one row for each
  # fixed phase. A test that needs one phase inserts one phase row. A test that
  # compares two phases inserts two phase rows for one execution, so the two
  # rows differ in the phase name only.

  @definition %{"schema_version" => 1}

  @doc "One stored study revision with a unique default identifier."
  def insert_revision(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          study_id: "study-#{System.unique_integer([:positive, :monotonic])}",
          revision: 1,
          schema_version: 1,
          definition: @definition
        },
        attrs
      )

    Repo.insert!(struct(StudyRevision, attrs))
  end

  @doc "One stored execution of the given revision."
  def insert_execution(revision, attrs \\ %{}) do
    attrs = Map.merge(%{study_revision_id: revision.id, state: :collecting_pilot}, attrs)

    Repo.insert!(StudyExecution.changeset(%StudyExecution{}, attrs))
  end

  @doc "One stored phase row of the given execution."
  def insert_phase(execution, phase) do
    Repo.insert!(StudyPhase.changeset(%StudyPhase{}, %{execution_id: execution.id, phase: phase}))
  end

  @doc "One revision, one execution, and the Pilot and Final collection phases."
  def study_with_two_phases do
    revision = insert_revision()
    execution = insert_execution(revision)

    %{
      revision: revision,
      execution: execution,
      pilot_phase: insert_phase(execution, :pilot_collection),
      final_phase: insert_phase(execution, :final_collection)
    }
  end

  @doc """
  One stored graph revision with two foothold hosts.

  Each host belongs to the one network segment, as the graph rules require. The
  graph holds no mission capability, so it is pre-attack feasible, and both
  hosts accept an initial foothold. A reservation test needs no other node type.
  """
  def insert_collection_graph(title \\ "study-collection") do
    graph = Graph.new(title)
    segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "external"})
    foothold = GraphFixtures.build_node(graph, Host, %{"name" => "foothold"})
    alternate = GraphFixtures.build_node(graph, Host, %{"name" => "alternate-foothold"})

    graph =
      graph
      |> Graph.add_node(segment)
      |> Graph.add_node(foothold)
      |> Graph.add_node(alternate)
      |> Graph.add_edge(contains(graph, segment, foothold))
      |> Graph.add_edge(contains(graph, segment, alternate))

    {:ok, inserted} = Graphs.insert(graph)

    %{graph: inserted, foothold: foothold, alternate_foothold: alternate}
  end

  defp contains(graph, segment, host) do
    Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}})
  end

  @doc "One typed optimization request for a stored graph."
  def optimization_request(graph, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        strategy: "cvss",
        budget: 1,
        seed: 7,
        simulation_params: nil,
        correlation_id: "study-optimization"
      )

    %RunOptimizationRequest{
      graph_revision_id: graph.revision_id,
      correlation_id: opts[:correlation_id],
      optimization_params: %OptimizationParams{
        strategy: opts[:strategy],
        budget: opts[:budget],
        seed: opts[:seed],
        simulation_params: opts[:simulation_params]
      }
    }
  end

  @doc "One typed simulation-backed optimization request for a stored graph."
  def simulation_backed_optimization_request(graph, foothold_id, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        budget: 1,
        seed: 7,
        trials: 1,
        iterations: 1,
        max_attempts: 1,
        correlation_id: "study-optimization"
      )

    optimization_request(graph,
      strategy: "simulation_informed",
      budget: opts[:budget],
      seed: opts[:seed],
      simulation_params: %SimulationSettings{
        monte_carlo_trials: opts[:trials],
        iterations_per_run: opts[:iterations],
        initial_foothold_node_id: foothold_id,
        max_attempts: opts[:max_attempts]
      },
      correlation_id: opts[:correlation_id]
    )
  end

  @doc "One typed simulation request for a stored graph and foothold."
  def simulation_request(graph, foothold, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        trials: 2,
        iterations: 1,
        max_attempts: 1,
        seed: 11,
        generate_seed: false,
        correlation_id: "study-simulation"
      )

    %RunSimulationRequest{
      graph_revision_id: graph.revision_id,
      correlation_id: opts[:correlation_id],
      simulation_params: %SimulationParams{
        monte_carlo_trials: opts[:trials],
        iterations_per_run: opts[:iterations],
        initial_foothold_node_id: foothold.id,
        generate_seed: opts[:generate_seed],
        seed: opts[:seed],
        max_attempts: opts[:max_attempts]
      }
    }
  end
end
