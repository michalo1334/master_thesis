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
