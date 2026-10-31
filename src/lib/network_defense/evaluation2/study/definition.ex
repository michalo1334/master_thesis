defmodule NetworkDefense.Evaluation2.Study.Definition do
  @moduledoc """
  Native study construction and derived scientific views.

  `parse/1` checks required known input fields and drops unknown keys.
  `resolve/1` binds persisted graphs and Host footholds, checks policy
  prerequisites, and freezes finite graph-derived mission-impact bounds.
  The public creation path is `NetworkDefense.Evaluation2.Study.create_revision/1`.

  Fixed tier order, declared budgets and alternatives determine comparisons and
  unique physical groups. CVSS is implicit and shared within each tier/budget.
  Pilot capacity is the coordinate-wise maximum candidate plus extra capacity.
  The definition owns these invariants once; task adapters use resolved plans.

  The definition freezes method/seed contracts and the configured measurement
  label. It stores no source YAML, credentials or operator revision checklist.
  """
  use Spectral

  alias NetworkDefense.DefenseActions.Registry, as: Actions

  alias NetworkDefense.Evaluation2.Study.Definition.{
    Candidate,
    Comparison,
    Defense,
    Family,
    Graph,
    Inference,
    Pilot,
    Precision,
    Provenance,
    SampleSize,
    Scoring,
    Simulation,
    Strategy,
    Study
  }

  alias NetworkDefense.Evaluation2.Study.Definition.Schema
  alias NetworkDefense.Evaluation2.Study.Randomness
  alias NetworkDefense.Graph.Graph, as: DomainGraph
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Nodes.{Host, MissionCapability}
  alias NetworkDefense.Optimization.Contracts.OptimizationParams
  alias NetworkDefense.Optimization.{SimulationObjective, TopologySegmentationStrategy}
  alias NetworkDefense.Rules.Registry, as: Rules
  alias NetworkDefense.Simulation.MissionImpact

  @type t :: %__MODULE__{
          study: Study.t(),
          seed: non_neg_integer(),
          family: Family.t(),
          analysis: Inference.t(),
          defense: Defense.t(),
          simulation: Simulation.t(),
          tiers: [Graph.t()],
          pilot: Pilot.t(),
          provenance: Provenance.t()
        }
  defstruct [
    :study,
    :seed,
    :family,
    :analysis,
    :defense,
    :simulation,
    :tiers,
    :pilot,
    :provenance
  ]

  @type family :: Family.t()
  @type pilot :: Pilot.t()
  @type comparison :: Comparison.t()
  @type strategy :: Strategy.t()
  @type candidate :: Candidate.t()
  @type graph :: Graph.t()
  @tiers ["small", "medium", "large"]
  @max_count 2_147_483_647
  @max_float 1.797_693_134_862_315_7e308
  @method "crossed-matching-betting-v1"

  @doc "Return the native fixed-sample numerical contract identity."
  def method, do: @method

  @doc "Construct a typed declaration and validate its counts, policies and seed allocation."
  def parse(attrs) do
    with :ok <- Schema.validate(attrs),
         {:ok, definition} <- construct(attrs),
         :ok <- validate_declarations(definition),
         :ok <- validate_seeds(definition) do
      precision = %{
        definition.pilot.precision
        | target_half_width: definition.pilot.precision.target_half_width / 1
      }

      {:ok, %{definition | pilot: %{definition.pilot | precision: precision}}}
    end
  end

  @doc "Resolve graph/Host inputs and freeze model bounds before revision insertion."
  def resolve(%__MODULE__{} = definition) do
    with {:ok, tiers} <- resolve_tiers(definition.tiers, definition) do
      {:ok, %{definition | tiers: tiers}}
    end
  end

  @doc "Derive collected Pilot row/column capacity from candidates and extra pool counts."
  def pilot_capacity(%__MODULE__{pilot: pilot}) do
    %SampleSize{
      plans: Enum.max_by(pilot.candidates, & &1.plans).plans + pilot.extra_pool.plans,
      attacks: Enum.max_by(pilot.candidates, & &1.attacks).attacks + pilot.extra_pool.attacks
    }
  end

  # Group coordinates are global; item positions belong to a phase-run plan.
  @doc "Return globally positioned groups in tier/budget order, with CVSS before alternatives."
  def collection_groups(%__MODULE__{tiers: tiers}) do
    for tier <- tiers,
        budget <- tier.budgets,
        strategy <- [%Strategy{key: :cvss, scoring: nil} | tier.alternatives] do
      %{tier: tier.tier, budget: budget, strategy: strategy}
    end
    |> Enum.with_index(fn group, position -> Map.put(group, :position, position) end)
  end

  @doc "Project the canonical alternative-versus-CVSS family from unique physical groups."
  def comparisons(definition) do
    groups = collection_groups(definition)

    for tier <- definition.tiers, budget <- tier.budgets, strategy <- tier.alternatives do
      %Comparison{
        tier: tier.tier,
        budget: budget,
        alternative: strategy.key,
        reference: :cvss,
        outcome: "mission_impact",
        group_position: group_position(groups, tier.tier, budget, strategy.key),
        reference_group_position: group_position(groups, tier.tier, budget, :cvss)
      }
    end
  end

  defp group_position(groups, tier, budget, key) do
    Enum.find(groups, &(&1.tier == tier and &1.budget == budget and &1.strategy.key == key)).position
  end

  @doc "Intersect the shared action policy with the existing strategy's supported actions."
  def effective_action_types(%__MODULE__{defense: defense}, key) do
    supported =
      case key do
        :cvss -> [:patch_vulnerability]
        :topology_segmentation -> [:block_segment_reachability]
        _ -> Actions.values()
      end

    Enum.filter(defense.allowed_action_types, &(&1 in supported))
  end

  @doc "Return the shared feasibility requirement inherited by selection and simulation."
  def require_feasibility?(%__MODULE__{defense: defense}), do: defense.feasibility == :required

  defp construct(a) do
    # Enum conversion searches registered values; submitted text never creates atoms.
    with {:ok, actions} <- enums(a["defense"]["allowed_action_types"], Actions.values()),
         {:ok, rules} <- enums(a["simulation"]["rules"], Rules.values()),
         {:ok, tiers} <- construct_tiers(a["tiers"]) do
      {:ok,
       %__MODULE__{
         study: %Study{id: a["study"]["id"], revision: a["study"]["revision"]},
         seed: a["seed"],
         family: %Family{id: a["family"]["id"], alpha: a["family"]["alpha"]},
         analysis: %Inference{confidence_level: a["analysis"]["confidence_level"]},
         defense: %Defense{
           feasibility:
             if(a["defense"]["feasibility"] == "unrestricted", do: :unrestricted, else: :required),
           allowed_action_types: actions
         },
         simulation: %Simulation{
           iterations_per_run: a["simulation"]["iterations_per_run"],
           max_attempts: a["simulation"]["max_attempts"],
           rules: rules
         },
         tiers: tiers,
         pilot: %Pilot{
           candidates:
             Enum.map(
               a["pilot"]["candidates"],
               &%Candidate{id: &1["id"], plans: &1["plans"], attacks: &1["attacks"]}
             ),
           extra_pool: %SampleSize{
             plans: a["pilot"]["extra_pool"]["plans"],
             attacks: a["pilot"]["extra_pool"]["attacks"]
           },
           precision: %Precision{
             outer_subsamples: a["pilot"]["precision"]["outer_subsamples"],
             target_half_width: a["pilot"]["precision"]["target_half_width"],
             guard_quantile: a["pilot"]["precision"]["guard_quantile"]
           }
         },
         provenance: %Provenance{
           method: @method,
           seed_contract: Randomness.contract(),
           environment_label:
             Application.get_env(:network_defense, :measured_environment_revision)
         }
       }}
    end
  end

  defp construct_tiers(attrs) do
    Enum.reduce_while(@tiers, {:ok, []}, fn tier, {:ok, result} ->
      a = attrs[tier]

      case construct_strategies(a["alternatives"]) do
        {:ok, alternatives} ->
          {:cont,
           {:ok,
            result ++
              [
                %Graph{
                  tier: tier,
                  graph_revision_id: a["graph_revision_id"],
                  initial_foothold_node_id: a["foothold_node_id"],
                  budgets: a["budgets"],
                  alternatives: alternatives,
                  mission_impact_bound: %{minimum: 0.0, maximum: 0.0}
                }
              ]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp construct_strategies(attrs) do
    Enum.reduce_while(attrs, {:ok, []}, fn a, {:ok, result} ->
      allowed = OptimizationParams.strategy_values() -- [:cvss, :null]

      with {:ok, [key]} <- enums([a["strategy"]], allowed),
           {:ok, scoring} <- construct_scoring(key, a["scoring"]) do
        {:cont, {:ok, result ++ [%Strategy{key: key, scoring: scoring}]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp construct_scoring(key, attrs) do
    cond do
      OptimizationParams.requires_simulation_params?(key) and is_map(attrs) ->
        with {:ok, [objective]} <- enums([attrs["objective"]], SimulationObjective.values()),
             true <- valid_count?(attrs["monte_carlo_trials"]) do
          {:ok, %Scoring{objective: objective, monte_carlo_trials: attrs["monte_carlo_trials"]}}
        else
          _ -> invalid("invalid_scoring")
        end

      OptimizationParams.requires_simulation_params?(key) ->
        invalid("scoring_required")

      is_nil(attrs) ->
        {:ok, nil}

      true ->
        invalid("unsupported_scoring")
    end
  end

  defp enums(names, allowed) do
    values = Enum.map(names, fn name -> Enum.find(allowed, &(Atom.to_string(&1) == name)) end)
    if Enum.any?(values, &is_nil/1), do: invalid("unsupported_value"), else: {:ok, values}
  end

  defp validate_declarations(d) do
    with :ok <- validate_sizes(d),
         :ok <- validate_probabilities(d),
         :ok <- validate_uniqueness(d) do
      if Enum.any?(collection_groups(d), &(effective_action_types(d, &1.strategy.key) == [])),
        do: invalid("unusable_action_policy"),
        else: :ok
    end
  end

  defp validate_sizes(d) do
    capacity = pilot_capacity(d)

    counts =
      [
        d.study.revision,
        d.simulation.iterations_per_run,
        d.simulation.max_attempts,
        d.pilot.precision.outer_subsamples,
        capacity.plans,
        capacity.attacks
      ] ++
        Enum.flat_map(d.tiers, & &1.budgets)

    cond do
      not Enum.all?(counts, &valid_count?/1) ->
        invalid("invalid_count")

      not (is_integer(d.seed) and d.seed >= 0 and d.seed < Randomness.modulus()) ->
        invalid("invalid_seed")

      true ->
        :ok
    end
  end

  defp valid_count?(value), do: is_integer(value) and value > 0 and value <= @max_count

  defp validate_probabilities(d) do
    fractions = [d.family.alpha, d.analysis.confidence_level, d.pilot.precision.guard_quantile]

    cond do
      not Enum.all?(fractions, &(finite?(&1) and &1 > 0 and &1 < 1)) ->
        invalid("invalid_probability")

      not (finite?(d.pilot.precision.target_half_width) and
               d.pilot.precision.target_half_width > 0) ->
        invalid("invalid_precision")

      true ->
        :ok
    end
  end

  defp validate_uniqueness(d) do
    cond do
      not unique?(d.defense.allowed_action_types) or not unique?(d.simulation.rules) ->
        invalid("duplicate_value")

      not unique?(Enum.map(d.pilot.candidates, & &1.id)) ->
        invalid("duplicate_candidate")

      not unique?(Enum.map(d.pilot.candidates, &{&1.plans, &1.attacks})) ->
        invalid("duplicate_candidate_counts")

      Enum.any?(d.tiers, &duplicate_tier_values?/1) ->
        invalid("duplicate_tier_value")

      true ->
        :ok
    end
  end

  defp duplicate_tier_values?(tier),
    do: not unique?(tier.budgets) or not unique?(Enum.map(tier.alternatives, & &1.key))

  defp unique?(list), do: length(list) == MapSet.size(MapSet.new(list))

  @doc false
  def finite?(value) when is_integer(value),
    do: value <= @max_float and value >= -@max_float

  def finite?(value) when is_float(value),
    do: abs(value) <= @max_float

  def finite?(_), do: false

  defp resolve_tiers(tiers, definition) do
    Enum.reduce_while(tiers, {:ok, []}, fn tier, {:ok, resolved} ->
      with {:ok, revision} <- Ecto.UUID.cast(tier.graph_revision_id),
           {:ok, foothold} <- Ecto.UUID.cast(tier.initial_foothold_node_id),
           %DomainGraph{} = graph <- Graphs.load_revision(revision),
           %{type: Host} <- DomainGraph.node(graph, foothold),
           :ok <- graph_policy(graph, tier, definition),
           {:ok, bound} <- model_bound(graph) do
        {:cont,
         {:ok,
          resolved ++
            [
              %{
                tier
                | graph_revision_id: revision,
                  initial_foothold_node_id: foothold,
                  mission_impact_bound: %{minimum: 0.0, maximum: bound}
              }
            ]}}
      else
        _ -> {:halt, invalid("invalid_graph_input", ["tiers", tier.tier])}
      end
    end)
  end

  defp graph_policy(graph, tier, definition) do
    feasible =
      not require_feasibility?(definition) or
        MissionImpact.pre_attack_feasible?(graph)

    topology_ready =
      if Enum.any?(tier.alternatives, &(&1.key == :topology_segmentation)) do
        params = %OptimizationParams{
          initial_foothold_node_id: tier.initial_foothold_node_id,
          seed: 0
        }

        match?(
          {:ok, _},
          TopologySegmentationStrategy.new(graph, params)
        )
      else
        true
      end

    if feasible and topology_ready, do: :ok, else: :error
  end

  defp model_bound(graph) do
    weights =
      graph
      |> DomainGraph.nodes()
      |> Enum.filter(&(&1.type == MissionCapability))
      |> Enum.map(& &1.data.impact_weight)

    if Enum.all?(weights, &(finite?(&1) and &1 > 0)) do
      bound = Enum.reduce(weights, 0.0, &(&1 + &2))
      if finite?(bound), do: {:ok, bound}, else: :error
    else
      :error
    end
  rescue
    ArithmeticError -> :error
  end

  defp validate_seeds(d) do
    case Randomness.validate(d) do
      :ok -> :ok
      {:error, _} -> invalid("seed_collision")
    end
  end

  defp invalid(code, path \\ []),
    do: {:error, Schema.error(code, path, "The definition contains an invalid declaration.")}
end
