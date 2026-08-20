defmodule NetworkDefense.Evaluation.Contracts.EvaluationManifest do
  @moduledoc """
  Strict structural validation of an evaluation manifest JSON document.

  The contract parses JSON and checks structure. It rejects unknown fields,
  invalid versions, invalid source combinations, invalid UUIDs, empty or
  duplicate budgets, strategies, or selection seeds, and invalid numeric
  values. Errors carry a JSON-path string for the dashboard.
  """

  @schema_version 1
  @known_strategies ~w(null random cvss topology_segmentation simulation_informed simulated_annealing)
  @known_objectives ~w(mission_then_blast_radius)
  @known_generators ~w(enterprise)
  @root_fields ~w(schema_version model_version id source attacker model budgets strategies selection_seeds evaluation)

  @type error :: %{path: String.t(), message: String.t()}

  @spec parse(String.t()) :: {:ok, map()} | {:error, [error()]}
  def parse(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, manifest} -> validate(manifest)
      {:error, _reason} -> {:error, [%{path: "$", message: "invalid JSON"}]}
    end
  end

  @spec validate(map()) :: {:ok, map()} | {:error, [error()]}
  def validate(manifest) when is_map(manifest) do
    errors =
      []
      |> check_unknown_fields(manifest)
      |> check_schema_version(manifest)
      |> check_model_version(manifest)
      |> check_id(manifest)
      |> check_source(manifest)
      |> check_attacker(manifest)
      |> check_model(manifest)
      |> check_budgets(manifest)
      |> check_strategies(manifest)
      |> check_selection_seeds(manifest)
      |> check_evaluation(manifest)

    if errors == [], do: {:ok, manifest}, else: {:error, errors}
  end

  def validate(_manifest), do: {:error, [%{path: "$", message: "manifest must be a JSON object"}]}

  defp check_unknown_fields(errors, manifest) do
    Enum.reduce(Map.keys(manifest) -- @root_fields, errors, fn key, acc ->
      [%{path: "$.#{key}", message: "unknown field"} | acc]
    end)
  end

  defp check_unknown_nested(errors, path, map, allowed) when is_map(map) do
    Enum.reduce(Map.keys(map) -- allowed, errors, fn key, acc ->
      [%{path: "#{path}.#{key}", message: "unknown field"} | acc]
    end)
  end

  defp check_schema_version(errors, manifest) do
    case manifest do
      %{"schema_version" => @schema_version} ->
        errors

      %{"schema_version" => version} when is_integer(version) ->
        [%{path: "schema_version", message: "unsupported version #{version}"} | errors]

      _ ->
        [%{path: "schema_version", message: "must be an integer"} | errors]
    end
  end

  defp check_model_version(errors, manifest) do
    case manifest do
      %{"model_version" => version} when is_binary(version) and byte_size(version) > 0 -> errors
      _ -> [%{path: "model_version", message: "must be a non-empty string"} | errors]
    end
  end

  defp check_id(errors, manifest) do
    case manifest do
      %{"id" => id} when is_binary(id) and byte_size(id) > 0 -> errors
      _ -> [%{path: "id", message: "must be a non-empty string"} | errors]
    end
  end

  defp check_source(errors, manifest) do
    case manifest do
      %{"source" => %{"type" => "topology"} = source} ->
        errors
        |> check_unknown_nested("source", source, ~w(type generator hosts seed))
        |> check_topology_source(source)

      %{"source" => %{"type" => "graph_revision"} = source} ->
        errors
        |> check_unknown_nested("source", source, ~w(type graph_revision_id))
        |> check_graph_revision_source(source)

      %{"source" => %{"type" => type}} when is_binary(type) ->
        [%{path: "source.type", message: "unknown source type #{type}"} | errors]

      %{"source" => _} ->
        [%{path: "source.type", message: "must be \"topology\" or \"graph_revision\""} | errors]

      _ ->
        [%{path: "source", message: "is required"} | errors]
    end
  end

  defp check_topology_source(errors, source) do
    errors
    |> check_topology_generator(source)
    |> check_topology_hosts(source)
    |> check_topology_seed(source)
  end

  defp check_topology_generator(errors, source) do
    case source do
      %{"generator" => generator} when generator in @known_generators ->
        errors

      %{"generator" => generator} when is_binary(generator) ->
        [%{path: "source.generator", message: "unknown generator #{generator}"} | errors]

      _ ->
        [%{path: "source.generator", message: "is required"} | errors]
    end
  end

  defp check_topology_hosts(errors, source) do
    case source do
      %{"hosts" => hosts} when is_integer(hosts) and hosts >= 8 ->
        errors

      %{"hosts" => hosts} when is_integer(hosts) ->
        [%{path: "source.hosts", message: "must be an integer >= 8"} | errors]

      _ ->
        [%{path: "source.hosts", message: "must be an integer"} | errors]
    end
  end

  defp check_topology_seed(errors, source) do
    case source do
      %{"seed" => seed} when is_integer(seed) and seed >= 0 ->
        errors

      %{"seed" => seed} when is_integer(seed) ->
        [%{path: "source.seed", message: "must be >= 0"} | errors]

      _ ->
        [%{path: "source.seed", message: "must be an integer"} | errors]
    end
  end

  defp check_graph_revision_source(errors, source) do
    case source do
      %{"graph_revision_id" => revision_id} ->
        if valid_uuid?(revision_id) do
          errors
        else
          [%{path: "source.graph_revision_id", message: "must be a valid UUID"} | errors]
        end

      _ ->
        [%{path: "source.graph_revision_id", message: "is required"} | errors]
    end
  end

  defp check_attacker(errors, manifest) do
    case manifest do
      %{"attacker" => %{"entry_host" => entry_host} = attacker} ->
        errors
        |> check_unknown_nested("attacker", attacker, ~w(entry_host max_attempts))
        |> check_entry_host(entry_host)
        |> check_max_attempts(attacker)
        |> check_source_selector_combination(manifest)

      %{"attacker" => _} ->
        [%{path: "attacker.entry_host", message: "is required"} | errors]

      _ ->
        [%{path: "attacker", message: "is required"} | errors]
    end
  end

  defp check_entry_host(errors, entry_host) do
    errors
    |> check_entry_host_unknown_fields(entry_host)
    |> check_entry_host_value(entry_host)
  end

  defp check_entry_host_unknown_fields(errors, entry_host) do
    case entry_host do
      %{"type" => type} when is_binary(type) ->
        check_unknown_nested(errors, "attacker.entry_host", entry_host, ~w(type value))

      _ ->
        errors
    end
  end

  defp check_entry_host_value(errors, entry_host) do
    case entry_host do
      %{"type" => "semantic_key", "value" => value}
      when is_binary(value) and byte_size(value) > 0 ->
        errors

      %{"type" => "semantic_key", "value" => _} ->
        [%{path: "attacker.entry_host.value", message: "must be a non-empty string"} | errors]

      %{"type" => "node_id", "value" => value} ->
        if valid_uuid?(value) do
          errors
        else
          [%{path: "attacker.entry_host.value", message: "must be a valid UUID"} | errors]
        end

      %{"type" => type} when is_binary(type) ->
        [%{path: "attacker.entry_host.type", message: "unknown selector type #{type}"} | errors]

      _ ->
        [%{path: "attacker.entry_host", message: "is required"} | errors]
    end
  end

  defp check_model(errors, manifest) do
    case manifest do
      %{"model" => %{"objective" => objective} = model} ->
        errors
        |> check_unknown_nested("model", model, ~w(objective require_pre_attack_feasibility))
        |> check_model_objective(objective)
        |> check_model_feasibility(model)

      %{"model" => _} ->
        [%{path: "model.objective", message: "is required"} | errors]

      _ ->
        [%{path: "model", message: "is required"} | errors]
    end
  end

  defp check_model_objective(errors, objective) do
    if objective in @known_objectives do
      errors
    else
      [%{path: "model.objective", message: "unknown objective #{objective}"} | errors]
    end
  end

  defp check_model_feasibility(errors, model) do
    case model do
      %{"require_pre_attack_feasibility" => value} when is_boolean(value) ->
        errors

      _ ->
        [
          %{path: "model.require_pre_attack_feasibility", message: "must be a boolean"}
          | errors
        ]
    end
  end

  defp check_source_selector_combination(errors, manifest) do
    source_type = get_in(manifest, ["source", "type"])
    selector_type = get_in(manifest, ["attacker", "entry_host", "type"])

    case {source_type, selector_type} do
      {"topology", "semantic_key"} ->
        errors

      {"graph_revision", "node_id"} ->
        errors

      {source_type, selector_type} when is_binary(source_type) and is_binary(selector_type) ->
        [
          %{
            path: "attacker.entry_host.type",
            message:
              "source type #{source_type} requires entry_host type " <>
                expected_selector(source_type) <> ", got #{selector_type}"
          }
          | errors
        ]

      _ ->
        errors
    end
  end

  defp expected_selector("topology"), do: "\"semantic_key\""
  defp expected_selector("graph_revision"), do: "\"node_id\""
  defp expected_selector(_), do: "a matching selector"

  defp check_max_attempts(errors, attacker) do
    case attacker do
      %{"max_attempts" => max_attempts} when is_integer(max_attempts) and max_attempts > 0 ->
        errors

      %{"max_attempts" => max_attempts} when is_integer(max_attempts) ->
        [%{path: "attacker.max_attempts", message: "must be > 0"} | errors]

      _ ->
        [%{path: "attacker.max_attempts", message: "must be an integer"} | errors]
    end
  end

  defp check_budgets(errors, manifest) do
    case manifest do
      %{"budgets" => budgets} when is_list(budgets) and budgets != [] ->
        check_integer_list(errors, "budgets", budgets, &(&1 > 0), "must be > 0")

      %{"budgets" => []} ->
        [%{path: "budgets", message: "must not be empty"} | errors]

      %{"budgets" => _} ->
        [%{path: "budgets", message: "must be a list of integers"} | errors]

      _ ->
        [%{path: "budgets", message: "is required"} | errors]
    end
  end

  defp check_strategies(errors, manifest) do
    case manifest do
      %{"strategies" => strategies} when is_list(strategies) and strategies != [] ->
        errors = check_known_strategies(errors, strategies)

        if length(Enum.uniq(strategies)) == length(strategies) do
          errors
        else
          [%{path: "strategies", message: "must not contain duplicates"} | errors]
        end

      %{"strategies" => []} ->
        [%{path: "strategies", message: "must not be empty"} | errors]

      %{"strategies" => _} ->
        [%{path: "strategies", message: "must be a list of strings"} | errors]

      _ ->
        [%{path: "strategies", message: "is required"} | errors]
    end
  end

  defp check_known_strategies(errors, strategies) do
    Enum.reduce(strategies, errors, fn strategy, acc ->
      if strategy in @known_strategies do
        acc
      else
        [%{path: "strategies", message: "unknown strategy #{strategy}"} | acc]
      end
    end)
  end

  defp check_selection_seeds(errors, manifest) do
    case manifest do
      %{"selection_seeds" => seeds} when is_list(seeds) and seeds != [] ->
        errors = check_integer_list(errors, "selection_seeds", seeds, &(&1 >= 0), "must be >= 0")

        if length(Enum.uniq(seeds)) == length(seeds) do
          errors
        else
          [%{path: "selection_seeds", message: "must not contain duplicates"} | errors]
        end

      %{"selection_seeds" => []} ->
        [%{path: "selection_seeds", message: "must not be empty"} | errors]

      %{"selection_seeds" => _} ->
        [%{path: "selection_seeds", message: "must be a list of integers"} | errors]

      _ ->
        [%{path: "selection_seeds", message: "is required"} | errors]
    end
  end

  defp check_evaluation(errors, manifest) do
    case manifest do
      %{"evaluation" => %{"trials" => trials} = evaluation} ->
        errors
        |> check_unknown_nested("evaluation", evaluation, ~w(trials seed))
        |> check_evaluation_trials(trials)
        |> check_evaluation_seed(evaluation)

      %{"evaluation" => _} ->
        [%{path: "evaluation.trials", message: "is required"} | errors]

      _ ->
        [%{path: "evaluation", message: "is required"} | errors]
    end
  end

  defp check_evaluation_trials(errors, trials) do
    if is_integer(trials) and trials > 0 do
      errors
    else
      [%{path: "evaluation.trials", message: "must be an integer > 0"} | errors]
    end
  end

  defp check_evaluation_seed(errors, evaluation) do
    case evaluation do
      %{"seed" => seed} when is_integer(seed) and seed >= 0 ->
        errors

      %{"seed" => seed} when is_integer(seed) ->
        [%{path: "evaluation.seed", message: "must be >= 0"} | errors]

      _ ->
        [%{path: "evaluation.seed", message: "must be an integer"} | errors]
    end
  end

  defp check_integer_list(errors, path, values, predicate, message) do
    errors =
      Enum.reduce(values, errors, fn value, acc ->
        if is_integer(value) and predicate.(value) do
          acc
        else
          [%{path: path, message: "each value #{message}"} | acc]
        end
      end)

    if length(Enum.uniq(values)) == length(values) do
      errors
    else
      [%{path: path, message: "must not contain duplicates"} | errors]
    end
  end

  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp valid_uuid?(_value), do: false
end
