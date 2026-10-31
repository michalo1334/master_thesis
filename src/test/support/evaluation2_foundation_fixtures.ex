defmodule NetworkDefense.Evaluation2Test.FoundationFixtures do
  @moduledoc """
  Independent documents and small accessors for the Evaluation2 foundation boundary.

  The YAML text is the single source of the valid document, and the map form is
  the decoded YAML value. Unit cases therefore exercise the same document the
  operator submits. Overrides change one declared position, so a rejection case
  states exactly one deviation from a valid document.

  Declared values are deliberately non-canonical where the declaration order is
  meaningful: the medium tier declares budgets `[8, 4]` and alternatives in the
  reverse of intrinsic order. Derived views must keep the declared order.

  ## Interface assumptions

  Cases refer to the intended foundation interface. The declarations below are
  the points the main implementation must match; each one is stated in the
  document that defines it.

    * `NetworkDefense.Evaluation2.Study.Definition.parse/1` accepts one decoded
      YAML map with string keys and returns `{:ok, definition}` or
      `{:error, %Study.Error{category: :validation_failed}}`. It is the pure
      construction boundary: graph lookups and Host checks belong to
      `Study.create_revision/1`, so the unit cases in this directory run without
      a database or stored graphs.
    * The trusted definition exposes `study`, `seed`, `family`, `analysis`,
      `defense`, `simulation`, `tiers`, `pilot`, and `provenance`.
    * `tiers` is an ordered list in `Study.Tier.all/0` order. One tier value
      carries `tier`, `graph_revision_id`, the resolved foothold node, `budgets`
      in declared order, and `alternatives` in declared order.
    * One alternative carries its strategy key and, for a scored strategy only,
      a `scoring` value with `objective` and `monte_carlo_trials`.
    * `Definition.comparisons/1` returns the derived family in canonical order,
      `Definition.collection_groups/1` returns the derived physical groups, and
      `Definition.pilot_capacity/1` returns the collected plan and attack counts.
    * A frozen model bound is reachable from the resolved tier input or from the
      definition. `bound_range/1` accepts the documented shapes of that value.
  """

  alias NetworkDefense.Optimization.Contracts.OptimizationParams

  @small_graph_id "6f1d1c62-4d3f-4f2e-9a33-0c1b0e6f1a01"
  @medium_graph_id "6f1d1c62-4d3f-4f2e-9a33-0c1b0e6f1a02"
  @large_graph_id "6f1d1c62-4d3f-4f2e-9a33-0c1b0e6f1a03"

  @small_foothold_id "6f1d1c62-4d3f-4f2e-9a33-0c1b0e6f1b01"
  @medium_foothold_id "6f1d1c62-4d3f-4f2e-9a33-0c1b0e6f1b02"
  @large_foothold_id "6f1d1c62-4d3f-4f2e-9a33-0c1b0e6f1b03"

  @tier_graph_ids %{small: @small_graph_id, medium: @medium_graph_id, large: @large_graph_id}

  @tier_foothold_ids %{
    small: @small_foothold_id,
    medium: @medium_foothold_id,
    large: @large_foothold_id
  }

  @doc "Graph revision identifiers of the fixture document, by tier."
  def tier_graph_ids, do: @tier_graph_ids

  @doc "Foothold node identifiers of the fixture document, by tier."
  def tier_foothold_ids, do: @tier_foothold_ids

  @doc """
  Return the valid new-format study document as YAML text.

  `:tier_graphs` replaces the declared graph inputs. It maps a tier to
  `{graph_revision_id, foothold_node_id}`.
  """
  def valid_yaml(opts \\ []) do
    graphs = Keyword.get(opts, :tier_graphs, @tier_graph_ids)

    footholds = Keyword.get(opts, :tier_footholds, @tier_foothold_ids)

    """
    study:
      id: example-study
      revision: 1
    seed: 31415
    family:
      id: primary-family
      alpha: 0.05
    analysis:
      confidence_level: 0.95
    defense:
      feasibility: required
      allowed_action_types:
        - patch_vulnerability
        - block_segment_reachability
        - revoke_credential
    simulation:
      iterations_per_run: 12
      max_attempts: 3
      rules:
        - remote_service_exploitation
        - reuse_credential_rule
    tiers:
      small:
        graph_revision_id: "#{Map.fetch!(graphs, :small)}"
        foothold_node_id: "#{Map.fetch!(footholds, :small)}"
        budgets: [4, 8]
        alternatives:
          - strategy: random
          - strategy: simulation_informed
            scoring:
              objective: mission_impact_only
              monte_carlo_trials: 50
      medium:
        graph_revision_id: "#{Map.fetch!(graphs, :medium)}"
        foothold_node_id: "#{Map.fetch!(footholds, :medium)}"
        budgets: [8, 4]
        alternatives:
          - strategy: simulation_informed
            scoring:
              objective: mission_impact_only
              monte_carlo_trials: 50
          - strategy: random
      large:
        graph_revision_id: "#{Map.fetch!(graphs, :large)}"
        foothold_node_id: "#{Map.fetch!(footholds, :large)}"
        budgets: [4]
        alternatives:
          - strategy: random
    pilot:
      candidates:
        - id: smaller
          plans: 10
          attacks: 20
        - id: larger
          plans: 20
          attacks: 40
      extra_pool:
        plans: 10
        attacks: 20
      precision:
        outer_subsamples: 50
        target_half_width: 0.05
        guard_quantile: 0.90
    """
  end

  @doc "Return the decoded valid document as a string-keyed map."
  def valid_attrs(opts \\ []) do
    opts |> valid_yaml() |> decode_yaml!()
  end

  @doc """
  Return the valid document with one or more declared positions changed.

  An override is `{["family", "alpha"], 1.5}` to set a value and
  `{:delete, ["family", "alpha"]}` to remove a position.
  """
  def attrs_with(overrides) when is_list(overrides) do
    Enum.reduce(overrides, valid_attrs(), &apply_override/2)
  end

  defp apply_override({:delete, path}, attrs), do: delete_in(attrs, path)
  defp apply_override({path, value}, attrs), do: put_in_path(attrs, path, value)

  defp put_in_path(_map, [], value), do: value

  defp put_in_path(map, [key | rest], value) when is_map(map),
    do: Map.put(map, key, put_in_path(Map.get(map, key, %{}), rest, value))

  defp delete_in(map, [key]) when is_map(map), do: Map.delete(map, key)

  defp delete_in(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, delete_in(value, rest))
      :error -> map
    end
  end

  defp decode_yaml!(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, document} when is_map(document) -> document
      other -> raise "the fixture document is not a decoded mapping: #{inspect(other)}"
    end
  end

  @doc "Return the graph revision identifiers of one parsed definition, by tier."
  def graph_revision_ids(definition) do
    Map.new(definition.tiers, &{tier_name(&1), graph_revision_id(&1)})
  end

  @doc "Return the foothold node identifiers of one parsed definition, by tier."
  def foothold_node_ids(definition) do
    Map.new(definition.tiers, &{tier_name(&1), foothold_id(&1)})
  end

  @doc "Return the declared tier name of one tier value."
  def tier_name(%{tier: tier}), do: tier_name(tier)
  def tier_name(tier), do: to_string(tier)

  @doc "Return the declared budgets of one tier value."
  def budgets(tier), do: Map.fetch!(tier, :budgets)

  @doc "Return the declared alternatives of one tier value."
  def alternatives(tier), do: Map.fetch!(tier, :alternatives)

  @doc """
  Return the optimization strategy of one alternative or comparison side.

  The accepted shapes are the declared strategy key, a strategy name, and the
  strategy atom itself.
  """
  def strategy_name(%{key: key}), do: strategy_name(key)
  def strategy_name(%{strategy: strategy}), do: strategy_name(strategy)
  def strategy_name(%{alternative: alternative}), do: strategy_name(alternative)
  def strategy_name(strategy) when is_binary(strategy), do: String.to_existing_atom(strategy)
  def strategy_name(strategy) when is_atom(strategy), do: strategy

  @doc "Return true when the value names one supported primary alternative."
  def primary_strategy?(name) when is_atom(name), do: name in OptimizationParams.strategy_values()

  @doc "Return the scoring block of one alternative, or nil for a simple alternative."
  def scoring(%{} = alternative), do: Map.get(alternative, :scoring)

  @doc "Return the global group position of one collection group."
  def group_position(%{position: position}), do: position
  def group_position(%{group_position: position}), do: position

  @doc "Return the frozen graph revision identifier of one tier value."
  def graph_revision_id(tier), do: tier.graph_revision_id

  @doc "Return the frozen foothold node identifier of one tier value."
  def foothold_id(tier), do: tier.initial_foothold_node_id

  @doc """
  Return every key of one value, recursively.

  Structs contribute their data fields. Unknown-key projection and duplicated
  declarations are checked with this view, so the cases read the normalized
  value instead of one private helper.
  """
  def deep_keys(%_{} = struct), do: deep_keys(Map.from_struct(struct))

  def deep_keys(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | deep_keys(value)] end)

  def deep_keys(list) when is_list(list), do: Enum.flat_map(list, &deep_keys/1)
  def deep_keys(_value), do: []

  @doc "Return the number of declarations of one key inside one value."
  def key_count(value, key), do: value |> deep_keys() |> Enum.count(&(&1 == key))

  @doc "Return the lower and upper endpoints of a frozen model range."
  def bound_range(%{minimum: lower, maximum: upper}), do: {lower, upper}

  @doc "Return the model range frozen with one resolved tier."
  def model_bound(tier), do: tier.mission_impact_bound
end
