defmodule NetworkDefense.Evaluation.Final.Limits do
  @moduledoc false

  alias NetworkDefense.Evaluation.Final.Contracts.{FinalError, Request}

  # Final resource guard.
  #
  # The comparison endpoint allocates one resample array and runs one loop for
  # every requested replicate. The Pilot caps do not cover that endpoint, so
  # Final carries its own deployment caps: a replicate ceiling and a total work
  # ceiling. Both caps are required configuration, all-or-none. This library
  # holds no built-in values and never borrows a Pilot cap, so a missing or
  # malformed configuration fails closed with a bounded Final error.
  #
  # One work unit is one resample of one declared comparison over both plan
  # sides and the shared ordered attack columns. A work unit is a resource
  # guard. It is not a statistical setting, and the guard never changes a
  # computed value.
  #
  # The guard runs before Gust submission and again on every persisted request
  # that reaches a Final task. Result read-back performs no compute, so it does
  # not depend on the guard.

  @config_key NetworkDefense.Evaluation.Final.Limits
  @required_keys [:max_bootstrap_replicates, :max_total_work]

  @type limits :: %{
          max_bootstrap_replicates: pos_integer(),
          max_total_work: pos_integer()
        }

  @spec validate(Request.t()) :: :ok | {:error, FinalError.t()}
  def validate(%Request{} = request) do
    with {:ok, limits} <- fetch(), do: check(request, limits)
  end

  @doc """
  Read the required Final resource caps.

  A missing, partial, or malformed configuration is an error. There is no
  fallback value.
  """
  @spec fetch() :: {:ok, limits()} | {:error, FinalError.t()}
  def fetch do
    case Application.fetch_env(:network_defense, @config_key) do
      {:ok, config} -> parse(config)
      :error -> not_configured()
    end
  rescue
    _exception -> not_configured()
  end

  @doc """
  Work units for one validated request.

  The count multiplies the declared comparison count, the two plan sides, the
  shared attack columns, and the requested replicate count. Integer arithmetic
  never overflows, and the result is compared before any value reaches the
  compute service.
  """
  @spec work_units(Request.t()) :: non_neg_integer()
  def work_units(%Request{} = request) do
    length(request.expected_comparisons) *
      per_replicate_units(request) *
      request.analysis.bootstrap_replicates
  end

  defp per_replicate_units(%Request{} = request) do
    2 * request.plan_count * request.attacks_per_plan
  end

  defp check(%Request{} = request, %{
         max_bootstrap_replicates: max_replicates,
         max_total_work: max_work
       }) do
    with :ok <- check_replicates(request.analysis.bootstrap_replicates, max_replicates) do
      check_work(work_units(request), max_work)
    end
  end

  defp check_replicates(replicates, max)
       when is_integer(replicates) and is_integer(max) and replicates <= max,
       do: :ok

  defp check_replicates(_replicates, _max),
    do: {:error, FinalError.bootstrap_replicates_exceeded()}

  defp check_work(work, max) when is_integer(work) and is_integer(max) and work <= max, do: :ok
  defp check_work(_work, _max), do: {:error, FinalError.work_limit_exceeded()}

  # The container shape fails closed. A map must hold the two required atom
  # keys and no other key. A list must be a keyword list with the two required
  # keys and no other key. An unknown key, an improper list, a non-tuple entry,
  # a string key, or a boolean value is malformed configuration, not a missing
  # value, so a deployment mistake cannot pass unnoticed. No framework, default,
  # or environment value is added.
  defp parse(config) when is_map(config) do
    if Map.keys(config) -- @required_keys == [], do: read_values(config), else: malformed_error()
  end

  defp parse(config) when is_list(config) do
    if Keyword.keyword?(config) and uniq_keys(config) -- @required_keys == [] do
      read_values(first_values(config))
    else
      malformed_error()
    end
  end

  defp parse(_config), do: malformed_error()

  # A repeated keyword key keeps its first value, as a keyword lookup does.
  defp first_values(config) do
    Enum.reduce(config, %{}, fn {key, value}, acc -> Map.put_new(acc, key, value) end)
  end

  # A repeated key is one key, so the subset check must count it once.
  defp uniq_keys(config), do: config |> Keyword.keys() |> Enum.uniq()

  defp read_values(config) do
    if Enum.all?(@required_keys, fn key -> positive_integer?(Map.get(config, key)) end) do
      {:ok, Map.take(config, @required_keys)}
    else
      malformed_error()
    end
  end

  defp positive_integer?(value), do: is_integer(value) and value > 0

  defp not_configured,
    do: {:error, FinalError.configuration_invalid("Final resource limits are not configured.")}

  defp malformed_error,
    do: {:error, FinalError.configuration_invalid("Final resource limits are malformed.")}
end
