defmodule Mix.Tasks.Gen.Contracts do
  use Mix.Task
  @moduledoc false
  alias Mix.Tasks.Gen.Contracts.Registry

  @shortdoc "Generate TypeScript types for a contract category"

  @impl Mix.Task
  def run([category]) do
    Mix.Task.run("compile")
    Registry.generate_all(category)
    IO.puts("Generated #{Registry.output_path(category)}")
  end

  def run(_args), do: Mix.raise("expected exactly one category: mix gen.contracts <category>")
end
