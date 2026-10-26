defmodule NetworkDefense.Evaluation.StudyFixtures do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Collection
  alias NetworkDefense.Evaluation.Study.CollectionItems
  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.{StudyCollectionItem, StudyExecution, StudyPhase, StudyRevision}
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Graph.{Edge, Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment}

  alias NetworkDefense.Optimization.Contracts.{
    OptimizationParams,
    RunOptimizationRequest,
    SimulationSettings
  }

  alias NetworkDefense.Relationships.{Contains, Supports}
  alias NetworkDefense.Repo
  alias NetworkDefense.Rules.Registry, as: RulesRegistry
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

  @doc """
  One revision, one execution, and the Pilot and Final collection phases.

  A mapped collection task reads the normalized definition from the stored
  revision, so a collection fixture stores the definition it executes.
  """
  def study_with_two_phases(definition \\ nil) do
    revision = insert_revision(revision_attrs(definition))
    execution = insert_execution(revision)

    %{
      revision: revision,
      execution: execution,
      pilot_phase: insert_phase(execution, :pilot_collection),
      final_phase: insert_phase(execution, :final_collection)
    }
  end

  defp revision_attrs(nil), do: %{}

  defp revision_attrs(%Definition{} = definition),
    do: %{definition: Definition.to_params(definition)}

  @doc """
  One stored graph revision with two foothold hosts.

  Each host belongs to the one network segment, as the graph rules require. The
  graph holds no mission capability by default, so it is pre-attack feasible, and
  both hosts accept an initial foothold. A reservation test needs no other node
  type. Pass `mission: true` to add mission capabilities that the foothold can
  affect.
  """
  def insert_collection_graph(title \\ "study-collection", opts \\ []) do
    graph = Graph.new(title)
    segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "external"})
    foothold = GraphFixtures.build_node(graph, Host, %{"name" => "foothold"})
    alternate = GraphFixtures.build_node(graph, Host, %{"name" => "alternate-foothold"})

    graph =
      graph
      |> Graph.add_node(segment)
      |> Graph.add_node(foothold)
      |> Graph.add_node(alternate)
      |> add_contains(segment, foothold)
      |> add_contains(segment, alternate)
      |> add_mission_capabilities(foothold, alternate, Keyword.get(opts, :mission, false))

    {:ok, inserted} = Graphs.insert(graph)

    %{graph: inserted, foothold: foothold, alternate_foothold: alternate}
  end

  defp add_contains(graph, segment, host) do
    Graph.add_edge(graph, contains(graph, segment, host))
  end

  defp add_mission_capabilities(graph, _foothold, _alternate, false), do: graph

  defp add_mission_capabilities(graph, foothold, alternate, true) do
    exclusive = mission_capability(graph, "primary", 8.0)
    shared = mission_capability(graph, "secondary", 4.0)

    graph
    |> Graph.add_node(exclusive)
    |> Graph.add_node(shared)
    |> add_supports(foothold, exclusive)
    |> add_supports(foothold, shared)
    |> add_supports(alternate, shared)
  end

  defp mission_capability(graph, name, impact_weight) do
    GraphFixtures.build_node(graph, MissionCapability, %{
      "name" => name,
      "impact_weight" => impact_weight,
      "min_operational_support" => 1,
      "required_flows" => []
    })
  end

  defp add_supports(graph, host, capability) do
    Graph.add_edge(graph, relationship_edge(graph, host, capability, Supports))
  end

  defp relationship_edge(graph, from, to, type) do
    Edge.new(graph.id, from.id, to.id, %{type: Atom.to_string(type), data: %{}})
  end

  defp contains(graph, segment, host) do
    Edge.new(graph.id, segment.id, host.id, %{type: Atom.to_string(Contains), data: %{}})
  end

  @doc """
  Executes every declared collection item of one replica and returns the stored
  rows in canonical item order.
  """
  def collect_pilot_items(
        %StudyExecution{} = execution,
        %StudyPhase{} = phase,
        %Definition{} = definition,
        replica_position \\ 0
      ) do
    {:ok, work} = Collection.build_collection_work(execution, phase, definition, replica_position)

    work
    |> Enum.reduce([], fn work_item, collected ->
      {:ok, item} =
        CollectionItems.get_or_create(phase.id, replica_position, work_item.item_position)

      {:ok, result} = Collection.run_collection_item(item.id)
      [Repo.get!(StudyCollectionItem, result.collection_item_id) | collected]
    end)
    |> Enum.reverse()
  end

  @collection_plan_count 5
  @collection_attack_count 10

  def collection_definition(graph, foothold) do
    definition =
      StudyConformance.definition()
      |> StudyConformance.put_in_definition(["graphs"], [collection_graph(graph, foothold)])
      |> StudyConformance.put_in_definition(["family", "comparisons"], [collection_comparison()])
      |> StudyConformance.put_in_definition(["pilot", "candidates"], [collection_candidate()])
      |> StudyConformance.put_in_definition(
        ["pilot", "collection", "plan_count_per_side"],
        @collection_plan_count
      )
      |> StudyConformance.put_in_definition(
        ["pilot", "collection", "attacks_per_plan"],
        @collection_attack_count
      )
      |> StudyConformance.put_in_definition(
        ["pilot", "collection", "selection_seeds"],
        collection_seeds()
      )
      |> StudyConformance.put_in_definition(
        ["pilot", "collection", "roots"],
        [%{"tier" => "core", "value" => 310_001}]
      )
      |> StudyConformance.put_in_definition(
        ["final", "collection", "roots"],
        [%{"tier" => "core", "value" => 320_001}]
      )
      |> StudyConformance.put_in_definition(["final", "analysis", "comparison_seeds"], [210_001])
      |> StudyConformance.put_in_definition(["simulation", "iterations_per_run"], 1)
      |> StudyConformance.put_in_definition(["simulation", "max_attempts"], 1)

    {:ok, parsed} = Definition.parse(definition)
    parsed
  end

  defp collection_graph(graph, foothold) do
    %{
      "tier" => "core",
      "graph_revision_id" => graph.revision_id,
      "initial_foothold_node_id" => foothold.id,
      "strategies" => [
        %{
          "key" => "cvss",
          "budget" => 1,
          "candidate_action_types" => ["patch_vulnerability", "revoke_credential"],
          "require_pre_attack_feasibility" => true
        },
        %{
          "key" => "null",
          "budget" => 1,
          "candidate_action_types" => ["patch_vulnerability"],
          "require_pre_attack_feasibility" => true
        }
      ]
    }
  end

  defp collection_comparison do
    %{
      "tier" => "core",
      "budget" => 1,
      "alternative" => "null",
      "reference" => "cvss",
      "outcome" => "mission_impact"
    }
  end

  defp collection_candidate do
    %{
      "id" => "small",
      "plan_count_per_side" => @collection_plan_count,
      "attacks_per_plan" => @collection_attack_count
    }
  end

  defp collection_seeds, do: [610_001, 610_002, 610_003, 610_004, 610_005]

  @doc "One typed optimization request for a stored graph."
  def optimization_request(graph, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        strategy: :cvss,
        budget: 1,
        seed: 7,
        candidate_action_types: [:patch_vulnerability, :revoke_credential],
        initial_foothold_node_id: nil,
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
        candidate_action_types: opts[:candidate_action_types],
        require_pre_attack_feasibility: true,
        initial_foothold_node_id: opts[:initial_foothold_node_id],
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
        objective: :mission_then_blast_radius,
        rules: RulesRegistry.values(),
        correlation_id: "study-optimization"
      )

    optimization_request(graph,
      strategy: :simulation_informed,
      budget: opts[:budget],
      seed: opts[:seed],
      candidate_action_types: [:patch_vulnerability, :revoke_credential],
      initial_foothold_node_id: foothold_id,
      simulation_params: %SimulationSettings{
        objective: opts[:objective],
        monte_carlo_trials: opts[:trials],
        iterations_per_run: opts[:iterations],
        max_attempts: opts[:max_attempts],
        rules: opts[:rules]
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
        rules: RulesRegistry.values(),
        require_pre_attack_feasibility: true,
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
        max_attempts: opts[:max_attempts],
        rules: opts[:rules],
        require_pre_attack_feasibility: opts[:require_pre_attack_feasibility]
      }
    }
  end
end
