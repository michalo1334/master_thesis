defmodule NetworkDefense.RuntimeConfig do
  @moduledoc """
  Reads runtime values from environment variables or mounted secret files.
  """

  def load_dotenv do
    if File.exists?(".env") do
      ".env"
      |> File.read!()
      |> String.split("\n")
      |> Enum.each(&load_dotenv_line/1)
    end
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

  defp load_dotenv_line("#" <> _), do: :ok

  defp load_dotenv_line(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] -> System.put_env(String.trim(key), String.trim(value))
      _ -> :ok
    end
  end
end
