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
end
