defmodule NetworkDefense.Evaluation.Comparison.DAGParser do
  @moduledoc false
  @behaviour Gust.DAG.Parser.Adapter

  alias Gust.DAG.Parser.Adapters.Elixir, as: ElixirParser

  @impl true
  def extension, do: ".exs"

  @impl true
  def parse_file(file_path) do
    ElixirParser.parse_file(file_path)
  end
end
