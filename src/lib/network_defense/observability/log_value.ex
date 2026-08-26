defmodule NetworkDefense.Observability.LogValue do
  @moduledoc false

  alias NetworkDefense.Evaluation.EvaluationRun
  alias NetworkDefense.Graph.Graph
  alias NetworkDefense.Optimization.Contracts.RunOptimizationRequest
  alias NetworkDefense.Optimization.ModelVariant
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Simulation.Experiment

  def normalize(value) when is_binary(value) do
    if String.valid?(value) and String.printable?(value) do
      value
    else
      %{encoding: "base64", value: Base.encode64(value)}
    end
  end

  def normalize(value) when is_boolean(value) or is_nil(value), do: value
  def normalize(value) when is_atom(value), do: Atom.to_string(value)
  def normalize(value) when is_number(value), do: value
  def normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def normalize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def normalize(%Date{} = value), do: Date.to_iso8601(value)
  def normalize(%Time{} = value), do: Time.to_iso8601(value)
  def normalize(%Decimal{} = value), do: Decimal.to_string(value)

  def normalize(%EvaluationRun{} = value) do
    value
    |> Map.take([
      :id,
      :evaluation_manifest_id,
      :source_graph_revision_id,
      :status,
      :failure_reason
    ])
    |> compact()
    |> normalize()
  end

  def normalize(%OptimizationRun{} = value) do
    value
    |> Map.take([
      :id,
      :graph_revision_id,
      :output_graph_revision_id,
      :evaluation_run_id,
      :model_variant,
      :strategy,
      :requested_budget,
      :used_budget,
      :runtime_ms,
      :status,
      :seed,
      :selection_seed
    ])
    |> Map.update!(:model_variant, &model_variant_wire/1)
    |> compact()
    |> normalize()
  end

  def normalize(%Experiment{} = value) do
    value
    |> Map.take([
      :id,
      :graph_revision_id,
      :evaluation_run_id,
      :optimization_run_id,
      :master_seed,
      :iteration_count,
      :max_attempts,
      :runtime_ms,
      :total_trials,
      :completed_trials,
      :status,
      :initial_foothold_node_id
    ])
    |> compact()
    |> normalize()
  end

  def normalize(%Graph{} = value) do
    value
    |> Map.take([
      :id,
      :folder_id,
      :revision_id,
      :parent_revision_id,
      :revision_number,
      :revision_kind,
      :title
    ])
    |> compact()
    |> normalize()
  end

  def normalize(%RunOptimizationRequest{} = value) do
    optimization_params =
      case value.optimization_params do
        nil ->
          nil

        params ->
          params
          |> Map.take([:strategy, :budget, :simulation_params])
          |> normalize_optimization_params()
      end

    %{
      graph_revision_id: value.graph_revision_id,
      correlation_id: value.correlation_id,
      optimization_params: optimization_params
    }
    |> compact()
    |> normalize()
  end

  def normalize(value) when is_list(value) do
    cond do
      List.improper?(value) ->
        inspect(value)

      List.ascii_printable?(value) ->
        List.to_string(value)

      true ->
        Enum.map(value, &normalize/1)
    end
  end

  def normalize(value) when is_tuple(value), do: value |> Tuple.to_list() |> normalize()

  def normalize(value)
      when is_pid(value) or is_port(value) or is_reference(value) or is_function(value),
      do: inspect(value)

  def normalize(%{__struct__: struct} = value) do
    value
    |> Map.from_struct()
    |> Map.put("__struct__", Atom.to_string(struct))
    |> normalize()
  end

  def normalize(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {normalize_key(key), normalize(nested_value)} end)
  end

  def normalize(value), do: inspect(value)

  defp normalize_optimization_params(params) do
    simulation_params =
      case params.simulation_params do
        nil ->
          nil

        value ->
          value
          |> Map.take([
            :monte_carlo_trials,
            :iterations_per_run,
            :initial_foothold_node_id,
            :seed,
            :generate_seed,
            :max_attempts
          ])
      end

    params
    |> Map.put(:simulation_params, simulation_params)
    |> compact()
  end

  defp model_variant_wire(nil), do: nil
  defp model_variant_wire(value), do: ModelVariant.to_wire(value)

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp normalize_key(key) when is_binary(key), do: normalize(key)
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: inspect(key)
end
