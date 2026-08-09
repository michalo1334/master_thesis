defmodule Mix.Tasks.Evaluate.Optimization do
  use Mix.Task

  @moduledoc """
  Runs an optimization synchronously and prints a JSON result record.

      mix evaluate.optimization --graph-revision-id REVISION_ID --strategy cvss --budget 3

      mix evaluate.optimization \\
        --graph-revision-id REVISION_ID --strategy simulated_annealing --budget 3 \\
        --trials 20 --iterations 10 --initial-foothold HOST_ID --max-attempts 1 --seed 42

  Options:

    * `--graph-revision-id` - graph revision to optimize (required)
    * `--strategy` - `cvss`, `simulation_informed`, `topology_segmentation` or
      `simulated_annealing` (required)
    * `--budget` - equal-action-count budget (required)
    * `--trials` - Monte Carlo trials for simulation strategies
    * `--iterations` - iterations per run for simulation strategies
    * `--initial-foothold` - initial foothold host id for simulation strategies
    * `--max-attempts` - max attacker attempts per step (default `1`)
    * `--seed` - deterministic seed; omitted means a random seed is generated
    * `--output` - write the JSON record to this file instead of stdout

  Simulation strategies require `--trials`, `--iterations` and
  `--initial-foothold`.
  """

  @shortdoc "Run an optimization synchronously and print a JSON result record"

  @requirements ["app.start"]

  @switches [
    graph_revision_id: :string,
    strategy: :string,
    budget: :integer,
    trials: :integer,
    iterations: :integer,
    initial_foothold: :string,
    max_attempts: :integer,
    seed: :integer,
    output: :string
  ]

  @simulation_strategies ["simulation_informed", "topology_segmentation", "simulated_annealing"]

  alias NetworkDefense.Optimization.Contracts.{OptimizationParams, RunOptimizationRequest}
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Simulation.Contracts.SimulationParams

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    with :ok <- validate_parse(positional, invalid),
         {:ok, request} <- build_request(opts) do
      case NetworkDefense.Optimizations.run(request) do
        {:ok, run} -> emit(record(load_with_actions(run)), opts[:output])
        {:error, reason} -> Mix.raise("optimization failed: #{reason}")
      end
    else
      {:error, reason} -> Mix.raise(reason)
    end
  end

  defp validate_parse([], []), do: :ok

  defp validate_parse(positional, invalid) do
    invalid_options = Enum.map(invalid, fn {option, _value} -> option end)
    {:error, "invalid options: #{Enum.join(positional ++ invalid_options, ", ")}"}
  end

  @doc "Builds and validates a `RunOptimizationRequest` from parsed options."
  @spec build_request(keyword()) :: {:ok, RunOptimizationRequest.t()} | {:error, String.t()}
  def build_request(opts) do
    strategy = Keyword.get(opts, :strategy)
    budget = Keyword.get(opts, :budget)
    graph_revision_id = Keyword.get(opts, :graph_revision_id)

    with :ok <- require_option(:strategy, strategy),
         :ok <- require_option(:budget, budget),
         :ok <- require_option(:graph_revision_id, graph_revision_id),
         {:ok, simulation_params} <- validate_simulation_params(strategy, opts),
         {:ok, optimization_params} <-
           validate_optimization_params(strategy, budget, simulation_params) do
      params = %{
        "graph_revision_id" => graph_revision_id,
        "correlation_id" => Ecto.UUID.generate(),
        "optimization_params" => OptimizationParams.to_params(optimization_params)
      }

      case RunOptimizationRequest.changeset(%RunOptimizationRequest{}, params) do
        %{valid?: true} = changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)}
        changeset -> {:error, changeset_errors(changeset)}
      end
    end
  end

  defp require_option(name, nil), do: {:error, "missing required option --#{name}"}
  defp require_option(_name, _value), do: :ok

  defp validate_simulation_params(strategy, opts) when strategy in @simulation_strategies do
    case SimulationParams.changeset(%SimulationParams{}, simulation_attrs(opts)) do
      %{valid?: true} = changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)}
      changeset -> {:error, changeset_errors(changeset)}
    end
  end

  defp validate_simulation_params(_strategy, _opts), do: {:ok, nil}

  defp validate_optimization_params(strategy, budget, simulation_params) do
    params = %{
      "strategy" => strategy,
      "budget" => budget,
      "simulation_params" => simulation_params && SimulationParams.to_params(simulation_params)
    }

    case OptimizationParams.changeset(%OptimizationParams{}, params) do
      %{valid?: true} = changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)}
      changeset -> {:error, changeset_errors(changeset)}
    end
  end

  defp simulation_attrs(opts) do
    %{
      "monte_carlo_trials" => opts[:trials],
      "iterations_per_run" => opts[:iterations],
      "initial_foothold_node_id" => opts[:initial_foothold],
      "seed" => opts[:seed],
      "generate_seed" => is_nil(opts[:seed]),
      "max_attempts" => Keyword.get(opts, :max_attempts, 1)
    }
  end

  defp changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, message ->
        String.replace(message, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{field |> Atom.to_string() |> String.capitalize()} #{Enum.join(messages, ", ")}"
    end)
  end

  defp load_with_actions(%OptimizationRun{} = run), do: OptimizationRuns.load(run.id)

  defp record(%OptimizationRun{} = run) do
    %{
      "optimization_run_id" => run.id,
      "graph_revision_id" => run.graph_revision_id,
      "output_graph_revision_id" => run.output_graph_revision_id,
      "strategy" => run.strategy,
      "requested_budget" => run.requested_budget,
      "used_budget" => run.used_budget,
      "runtime_ms" => run.runtime_ms,
      "status" => run.status,
      "seed" => run.seed,
      "simulation_config" => run.simulation_config,
      "actions" => Enum.map(run.actions, &action_record/1)
    }
  end

  defp action_record(action) do
    %{
      "position" => action.position,
      "action_type" => action.action_type,
      "target_id" => action.target_id,
      "cost" => action.cost
    }
  end

  defp emit(record, nil), do: IO.puts(Jason.encode!(record))

  defp emit(record, path) do
    File.write!(path, Jason.encode!(record))
  end
end
