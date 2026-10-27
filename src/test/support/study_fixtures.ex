defmodule NetworkDefense.Evaluation.StudyFixtures do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Collection
  alias NetworkDefense.Evaluation.Study.CollectionItems
  alias NetworkDefense.Evaluation.Study.Contracts.Definition
  alias NetworkDefense.Evaluation.Study.PhaseRuns
  alias NetworkDefense.Evaluation.Study.PilotOutcome

  alias NetworkDefense.Evaluation.{
    EvidenceSnapshot,
    FinalConformance,
    StudyCollectionItem,
    StudyExecution,
    StudyPhase,
    StudyRevision
  }

  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Graph.{Edge, Graph, Graphs}
  alias NetworkDefense.GraphFixtures
  alias NetworkDefense.Nodes.{Host, MissionCapability, NetworkSegment, Service}

  alias NetworkDefense.Optimization.Contracts.{
    OptimizationParams,
    RunOptimizationRequest,
    SimulationSettings
  }

  alias NetworkDefense.Relationships.{Contains, Runs, SegmentReachability, Supports}
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

  @doc "An executable study fixture adapted from the checked Final conformance documents."
  def final_conformance_fixture do
    FinalConformance.fixture()
    |> replace_heuristic()
  end

  @doc "A study definition for the executable Final conformance lifecycle fixture."
  @spec final_conformance_definition!() :: Definition.t()
  def final_conformance_definition! do
    request = FinalConformance.request()
    analysis = request["analysis"]

    StudyConformance.definition()
    |> put_in(["family", "id"], request["family_id"])
    |> put_in(
      ["pilot", "candidates", Access.at(1), "attacks_per_plan"],
      request["attacks_per_plan"]
    )
    |> put_in(["final", "analysis", "comparison_seeds"], request["comparison_seeds"])
    |> put_in(["final", "analysis", "alpha"], analysis["alpha"])
    |> put_in(["final", "analysis", "confidence_level"], analysis["confidence_level"])
    |> put_in(["final", "analysis", "test_alternative"], analysis["test_alternative"])
    |> put_in(["final", "analysis", "bootstrap_replicates"], analysis["bootstrap_replicates"])
    |> Definition.parse()
    |> fixture_ok!()
  end

  @doc """
  A journey definition with one stored graph for each declared tier.

  The Pilot collection runs real items on the stored graphs. The family,
  candidate, and analysis settings match the checked-in Final conformance
  examples, so the Final result the journey uses is the same validated source
  the other Final suites use. Each scoring block shrinks to one trial, one
  iteration, and one attempt, because a journey checks the lifecycle and not
  the scientific cost.
  """
  @spec conformance_journey_definition!(map(), map()) :: Definition.t()
  def conformance_journey_definition!(core, edge) do
    request = FinalConformance.request()
    analysis = request["analysis"]
    [core_graph, edge_graph] = StudyConformance.definition()["graphs"]

    StudyConformance.definition()
    |> put_in(["graphs"], [
      journey_graph(core_graph, core),
      journey_graph(edge_graph, edge)
    ])
    |> put_in(["family", "id"], request["family_id"])
    |> put_in(
      ["pilot", "candidates", Access.at(1), "attacks_per_plan"],
      request["attacks_per_plan"]
    )
    |> put_in(["pilot", "collection", "attacks_per_plan"], request["attacks_per_plan"])
    |> put_in(["final", "analysis", "comparison_seeds"], request["comparison_seeds"])
    |> put_in(["final", "analysis", "alpha"], analysis["alpha"])
    |> put_in(["final", "analysis", "confidence_level"], analysis["confidence_level"])
    |> put_in(["final", "analysis", "test_alternative"], analysis["test_alternative"])
    |> put_in(["final", "analysis", "bootstrap_replicates"], analysis["bootstrap_replicates"])
    |> put_in(["simulation", "iterations_per_run"], 1)
    |> put_in(["simulation", "max_attempts"], 1)
    |> Definition.parse()
    |> fixture_ok!()
  end

  defp journey_graph(graph, stored) do
    graph
    |> Map.put("graph_revision_id", stored.graph.revision_id)
    |> Map.put("initial_foothold_node_id", stored.foothold.id)
    |> Map.update!("strategies", fn strategies -> Enum.map(strategies, &shrink_scoring/1) end)
  end

  defp shrink_scoring(%{"scoring" => scoring} = strategy) do
    scoring =
      scoring
      |> Map.put("monte_carlo_trials", 1)
      |> Map.put("iterations_per_run", 1)
      |> Map.put("max_attempts", 1)

    Map.put(strategy, "scoring", scoring)
  end

  defp shrink_scoring(strategy), do: strategy

  @doc "Persist the executable Final conformance lifecycle through its Pilot source."
  def persist_final_conformance_lifecycle!(pilot_run_id, opts \\ []) do
    final_lifecycle(final_conformance_definition!(),
      candidate_id: "medium",
      state: Keyword.get(opts, :state, :collecting_final),
      outcome: Keyword.get(opts, :outcome, :recommended),
      pilot_run_id: pilot_run_id,
      revision_attrs: [id: FinalConformance.request()["study_revision_id"]]
    )
  end

  @doc """
  Persist the accepted Final collection snapshot and the ordered tier-run family,
  then enter Final analysis.

  The Final collection phase keeps no scalar Gust run. One phase-run row holds
  the one Gust run of each declared tier, in first-seen comparison order.
  """
  def accept_final_collection!(context, snapshot_id, run_ids \\ nil) do
    Repo.transaction(fn ->
      _snapshot = Repo.get!(EvidenceSnapshot, snapshot_id)
      phase = Repo.get!(StudyPhase, context.final_phase.id)
      execution = Repo.get!(StudyExecution, context.execution.id)

      if not is_nil(phase.snapshot_id) and phase.snapshot_id != snapshot_id do
        raise "the Final collection phase already accepts a different snapshot"
      end

      phase =
        phase |> StudyPhase.changeset(%{snapshot_id: snapshot_id, error: nil}) |> Repo.update!()

      phase_runs =
        link_final_phase_runs!(
          context.definition,
          phase,
          if(is_nil(run_ids), do: [], else: [run_ids: run_ids])
        )

      execution = accept_final_analysis_state!(execution)

      context
      |> Map.merge(%{execution: execution, final_phase: phase})
      |> Map.put(:final_phase_runs, phase_runs)
    end)
    |> case do
      {:ok, accepted} -> accepted
      {:error, reason} -> raise "could not accept Final collection: #{inspect(reason)}"
    end
  end

  @doc """
  Store one linked Gust run for each declared tier of a Final collection phase.

  A caller that needs only the ordered family, without a snapshot, uses this
  helper directly.
  """
  def link_final_phase_runs!(%Definition{} = definition, %StudyPhase{} = phase, opts \\ []) do
    {:ok, tiers} = Collection.tier_order(definition)
    run_ids = Keyword.get(opts, :run_ids, unique_run_ids(length(tiers)))

    tiers
    |> Enum.with_index()
    |> Enum.map(fn {tier, tier_position} ->
      {:ok, row} = PhaseRuns.get_or_create(phase, tier, tier_position)
      {:ok, linked} = PhaseRuns.link_gust_run(row, Enum.at(run_ids, tier_position))
      linked
    end)
  end

  # A Gust run belongs to one phase run, so a stored fixture family needs run
  # identifiers that no other stored row already holds.
  defp unique_run_ids(count) do
    base = 1_000_000 + System.unique_integer([:positive, :monotonic])
    Enum.map(0..(count - 1), &(base + &1))
  end

  @doc "One stored execution with a frozen Final selection and an accepted Pilot analysis phase."
  def final_lifecycle(%Definition{} = definition, opts \\ []) do
    candidate_id = Keyword.get(opts, :candidate_id, hd(definition.pilot.candidates).id)
    candidate = Enum.find(definition.pilot.candidates, &(&1.id == candidate_id))
    outcome_kind = Keyword.get(opts, :outcome, :recommended)

    outcome =
      case outcome_kind do
        :recommended ->
          PilotOutcome.to_params(%PilotOutcome{
            outcome: :recommended,
            candidate_id: candidate.id,
            plan_count_per_side: candidate.plan_count_per_side,
            attacks_per_plan: candidate.attacks_per_plan
          })

        :insufficient ->
          PilotOutcome.to_params(%PilotOutcome{
            outcome: :insufficient,
            reason: "no_passing_candidate"
          })
      end

    revision_attrs =
      definition
      |> revision_attrs()
      |> Map.merge(Map.new(Keyword.get(opts, :revision_attrs, [])))

    revision = insert_revision(revision_attrs)

    execution =
      insert_execution(revision, %{
        state: Keyword.get(opts, :state, :collecting_final),
        pilot_outcome: outcome,
        selected_candidate_id: candidate.id,
        selected_plan_count_per_side: candidate.plan_count_per_side,
        selected_attacks_per_plan: candidate.attacks_per_plan,
        pilot_override: outcome_kind == :insufficient
      })

    pilot_phase = insert_phase(execution, :pilot_analysis)

    pilot_phase =
      Repo.update!(
        StudyPhase.changeset(pilot_phase, %{
          gust_run_id: Keyword.get(opts, :pilot_run_id, 901),
          result_ref: outcome
        })
      )

    %{
      revision: revision,
      execution: execution,
      pilot_phase: pilot_phase,
      final_phase: insert_phase(execution, :final_collection),
      candidate: candidate,
      definition: definition
    }
  end

  defp accept_final_analysis_state!(%StudyExecution{state: :collecting_final} = execution) do
    execution
    |> StudyExecution.changeset(%{state: :analyzing_final})
    |> Repo.update!()
  end

  defp accept_final_analysis_state!(%StudyExecution{state: state} = execution)
       when state in [:analyzing_final, :succeeded],
       do: execution

  defp replace_heuristic("heuristic"), do: "simulated_annealing"
  defp replace_heuristic(value) when is_list(value), do: Enum.map(value, &replace_heuristic/1)

  defp replace_heuristic(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {key, replace_heuristic(item)} end)

  defp replace_heuristic(value), do: value

  defp fixture_ok!({:ok, value}), do: value
  defp fixture_ok!({:error, error}), do: raise("expected fixture, got: #{inspect(error)}")

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

    {graph, required_flows} =
      add_required_flow(graph, segment, Keyword.get(opts, :required_flow, false))

    graph =
      add_mission_capabilities(
        graph,
        foothold,
        alternate,
        Keyword.get(opts, :mission, false),
        required_flows
      )

    {:ok, inserted} = Graphs.insert(graph)

    %{
      graph: inserted,
      foothold: foothold,
      alternate_foothold: alternate,
      required_flows: required_flows
    }
  end

  # One declared flow needs a policy to the segment that runs the target service.
  # The option adds two flows with different source segments, so projection order
  # is comparable with the declared order.
  defp add_required_flow(graph, _segment, false), do: {graph, []}

  defp add_required_flow(graph, segment, true) do
    target_segment = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "internal"})
    target_host = GraphFixtures.build_node(graph, Host, %{"name" => "service-host"})
    dmz = GraphFixtures.build_node(graph, NetworkSegment, %{"name" => "dmz"})
    dmz_host = GraphFixtures.build_node(graph, Host, %{"name" => "dmz-host"})

    api =
      GraphFixtures.build_node(graph, Service, %{
        "name" => "api",
        "protocol" => "tcp",
        "port" => 8080
      })

    database =
      GraphFixtures.build_node(graph, Service, %{
        "name" => "db",
        "protocol" => "tcp",
        "port" => 5432
      })

    graph =
      graph
      |> Graph.add_node(target_segment)
      |> Graph.add_node(target_host)
      |> Graph.add_node(dmz)
      |> Graph.add_node(dmz_host)
      |> Graph.add_node(api)
      |> Graph.add_node(database)
      |> add_contains(target_segment, target_host)
      |> add_contains(dmz, dmz_host)
      |> Graph.add_edge(relationship_edge(graph, target_host, api, Runs))
      |> Graph.add_edge(relationship_edge(graph, target_host, database, Runs))
      |> add_policy(segment, target_segment)
      |> add_policy(dmz, target_segment)

    {graph,
     [
       %{"source_segment_id" => segment.id, "target_service_id" => api.id},
       %{"source_segment_id" => dmz.id, "target_service_id" => database.id}
     ]}
  end

  defp add_policy(graph, from, to) do
    Graph.add_edge(
      graph,
      relationship_edge(graph, from, to, SegmentReachability, %{"protocol" => "tcp"})
    )
  end

  defp add_contains(graph, segment, host) do
    Graph.add_edge(graph, contains(graph, segment, host))
  end

  defp add_mission_capabilities(graph, _foothold, _alternate, false, _required_flows), do: graph

  defp add_mission_capabilities(graph, foothold, alternate, true, required_flows) do
    exclusive = mission_capability(graph, "primary", 8.0, required_flows)
    shared = mission_capability(graph, "secondary", 4.0, [])

    graph
    |> Graph.add_node(exclusive)
    |> Graph.add_node(shared)
    |> add_supports(foothold, exclusive)
    |> add_supports(foothold, shared)
    |> add_supports(alternate, shared)
  end

  defp mission_capability(graph, name, impact_weight, required_flows) do
    GraphFixtures.build_node(graph, MissionCapability, %{
      "name" => name,
      "impact_weight" => impact_weight,
      "min_operational_support" => 1,
      "required_flows" => required_flows
    })
  end

  defp add_supports(graph, host, capability) do
    Graph.add_edge(graph, relationship_edge(graph, host, capability, Supports))
  end

  defp relationship_edge(graph, from, to, type, data \\ %{}) do
    Edge.new(graph.id, from.id, to.id, %{type: Atom.to_string(type), data: data})
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
