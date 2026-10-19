defmodule NetworkDefense.Evaluation.Pilot.Limits do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotError

  # Every Stage 4 snapshot, count, and work limit is required application
  # configuration. The application and the Stage 2 and Stage 3 paths start
  # without it. A Pilot call fails with one bounded typed error before snapshot
  # insertion or Gust run creation when the configuration is missing or
  # malformed.
  #
  # Values are supplied by test configuration and by manual-check commands.
  # No production value is invented here.

  @keys [
    :snapshot_payload_bytes,
    :snapshot_comparisons,
    :comparison_count,
    :candidate_count,
    :plans_per_side,
    :attack_columns,
    :work_items,
    :outer_subsamples,
    :bootstrap_replicates,
    :candidate_request_bytes
  ]

  @enforce_keys @keys
  defstruct @keys

  @type t :: %__MODULE__{
          snapshot_payload_bytes: pos_integer(),
          snapshot_comparisons: pos_integer(),
          comparison_count: pos_integer(),
          candidate_count: pos_integer(),
          plans_per_side: pos_integer(),
          attack_columns: pos_integer(),
          work_items: pos_integer(),
          outer_subsamples: pos_integer(),
          bootstrap_replicates: pos_integer(),
          candidate_request_bytes: pos_integer()
        }

  @spec keys() :: [atom()]
  def keys, do: @keys

  @spec fetch() :: {:ok, t()} | {:error, PilotError.t()}
  def fetch do
    case Application.fetch_env(:network_defense, __MODULE__) do
      {:ok, config} when is_list(config) -> build(config)
      {:ok, _malformed} -> {:error, invalid("Pilot limit configuration must be a keyword list.")}
      :error -> {:error, invalid("Pilot limit configuration is missing.")}
    end
  end

  defp build(config) do
    if Keyword.keyword?(config) do
      check_keys(config)
    else
      {:error, invalid("Pilot limit configuration must be a keyword list.")}
    end
  end

  defp check_keys(config) do
    keys = Keyword.keys(config)

    cond do
      keys -- @keys != [] ->
        {:error, invalid("Pilot limit configuration contains an unknown key.")}

      @keys -- keys != [] ->
        {:error, invalid("Pilot limit configuration is incomplete.")}

      true ->
        valid_values(config)
    end
  end

  defp valid_values(config) do
    values = Map.new(@keys, fn key -> {key, Keyword.get(config, key)} end)

    if Enum.all?(values, fn {_key, value} -> is_integer(value) and value > 0 end) do
      {:ok, struct!(__MODULE__, values)}
    else
      {:error, invalid("Every Pilot limit must be a positive integer.")}
    end
  end

  defp invalid(message) do
    PilotError.new("workflow_failed", "configuration_invalid", [], message)
  end
end
