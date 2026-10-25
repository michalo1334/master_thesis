defmodule NetworkDefense.RuntimeConfig do
  @moduledoc """
  Reads runtime values from environment variables or mounted secret files.
  """

  @type role :: :api | :worker

  @spec role() :: role()
  def role do
    case System.get_env("ROLE") do
      "api" -> :api
      "worker" -> :worker
      nil -> :worker
      value -> raise ArgumentError, "invalid ROLE: expected api or worker, got #{inspect(value)}"
    end
  end

  @spec api?() :: boolean()
  def api?, do: role() == :api

  @spec worker?() :: boolean()
  def worker?, do: role() == :worker

  @spec rabbitmq() :: keyword()
  def rabbitmq do
    [
      host: System.fetch_env!("RABBITMQ_HOST"),
      port: positive_integer_env("RABBITMQ_PORT"),
      virtual_host: System.fetch_env!("RABBITMQ_VIRTUAL_HOST"),
      username: System.fetch_env!("RABBITMQ_USERNAME"),
      password:
        read_secret("RABBITMQ_PASSWORD") ||
          raise("expected RABBITMQ_PASSWORD_FILE environment variable"),
      max_message_bytes: positive_integer_env("RABBITMQ_MAX_MESSAGE_BYTES"),
      result_inactivity_timeout_ms: positive_integer_env("RABBITMQ_RESULT_INACTIVITY_TIMEOUT_MS")
    ]
  end

  # _FILE paths are deployment-controlled mounted secrets.
  # sobelow_skip ["Traversal.FileModule"]
  def read_secret(name, default \\ nil) do
    case System.get_env(name <> "_FILE") do
      path when is_binary(path) ->
        path |> File.read!() |> String.trim()

      nil ->
        System.get_env(name) || default
    end
  end

  @pilot_limit_variables %{
    snapshot_payload_bytes: "EVALUATION_PILOT_MAX_SNAPSHOT_PAYLOAD_BYTES",
    snapshot_comparisons: "EVALUATION_PILOT_MAX_SNAPSHOT_COMPARISONS",
    comparison_count: "EVALUATION_PILOT_MAX_COMPARISONS",
    candidate_count: "EVALUATION_PILOT_MAX_CANDIDATES",
    plans_per_side: "EVALUATION_PILOT_MAX_PLANS_PER_SIDE",
    attack_columns: "EVALUATION_PILOT_MAX_ATTACK_COLUMNS",
    work_items: "EVALUATION_PILOT_MAX_WORK_ITEMS",
    outer_subsamples: "EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES",
    bootstrap_replicates: "EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES",
    candidate_request_bytes: "EVALUATION_PILOT_MAX_CANDIDATE_REQUEST_BYTES"
  }

  @study_collection_variables %{
    max_phase_items: "EVALUATION_STUDY_MAX_PHASE_ITEMS",
    max_gust_concurrency: "EVALUATION_STUDY_MAX_GUST_CONCURRENCY"
  }

  @doc """
  Reads the complete Stage 4 Pilot limit set from the environment.

  The set is all-or-none. `:unconfigured` means no variable is set, so the
  application starts and the Pilot paths fail with a bounded typed error.
  `{:error, message}` means the set is partial or malformed. Nothing here
  raises, so a Pilot configuration defect never blocks the application, the
  Stage 2 paths, or the Stage 3 paths.
  """
  @spec pilot_limits() :: {:ok, keyword()} | :unconfigured | {:error, String.t()}
  def pilot_limits do
    read_positive_set(
      @pilot_limit_variables,
      "only some Stage 4 Pilot limit variables are set; set all of them or none"
    )
  end

  @spec study_collection_limits() :: {:ok, keyword()} | :unconfigured | {:error, String.t()}
  def study_collection_limits do
    read_positive_set(
      @study_collection_variables,
      "only some study collection control variables are set; set all of them or none"
    )
  end

  defp read_positive_set(variables, partial_message) do
    values =
      Enum.map(variables, fn {key, variable} -> {key, variable, System.get_env(variable)} end)

    configured = Enum.reject(values, fn {_key, _variable, value} -> value in [nil, ""] end)

    cond do
      configured == [] ->
        :unconfigured

      Enum.count(configured) < Enum.count(values) ->
        {:error, partial_message}

      true ->
        parse_positive_set(configured)
    end
  end

  defp parse_positive_set(values) do
    Enum.reduce_while(values, {:ok, []}, fn {key, variable, value}, {:ok, acc} ->
      case Integer.parse(value) do
        {parsed, ""} when parsed > 0 ->
          {:cont, {:ok, [{key, parsed} | acc]}}

        _other ->
          {:halt, {:error, "#{variable} must be a positive integer, got #{inspect(value)}"}}
      end
    end)
    |> case do
      {:ok, limits} -> {:ok, Enum.reverse(limits)}
      error -> error
    end
  end

  @spec positive_integer_env(String.t()) :: pos_integer()
  def positive_integer_env(name) do
    name
    |> System.fetch_env!()
    |> parse_positive_integer(name)
  end

  @doc """
  Reads a positive-integer environment override, or returns `default` when the
  variable is unset.

  The whole value must be a positive integer. Any other value raises a
  descriptive startup error, so a typo cannot silently disable a limit.
  """
  @spec positive_integer_env(String.t(), pos_integer()) :: pos_integer()
  def positive_integer_env(name, default) when is_binary(name) do
    case System.get_env(name) do
      nil -> default
      value -> parse_positive_integer(value, name)
    end
  end

  defp parse_positive_integer(value, name) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _result -> raise ArgumentError, "#{name} must be a positive integer, got #{inspect(value)}"
    end
  end
end
