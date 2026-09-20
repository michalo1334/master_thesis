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

  defp positive_integer_env(name) do
    case Integer.parse(System.fetch_env!(name)) do
      {value, ""} when value > 0 -> value
      _result -> raise ArgumentError, "#{name} must be a positive integer"
    end
  end
end
