defmodule Mix.Tasks.Gen.Contracts do
  use Mix.Task
  @moduledoc false
  alias Mix.Tasks.Gen.Contracts.Registry

  @shortdoc "Generate TypeScript types from all contracts"

  @impl Mix.Task
  def run([]) do
    Mix.Task.run("compile")
    Registry.generate_all()
    IO.puts("Generated #{Registry.output_path()}")
  end

  def run(_args), do: Mix.raise("mix gen.contracts does not accept arguments")
end
