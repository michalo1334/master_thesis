defmodule Mix.Tasks.Gen.Contracts do
  use Mix.Task
  @moduledoc false
  alias Mix.Tasks.Gen.Contracts.Registry

  @shortdoc "Generate TypeScript types for contract categories"

  @impl Mix.Task
  def run([]), do: generate("dashboard", :all)
  def run([output]), do: generate(output, :all)
  def run([output | categories]), do: generate(output, categories)

  defp generate(output, categories) do
    Mix.Task.run("compile")
    Registry.generate_all(output, categories)
    IO.puts("Generated #{Registry.output_path(output)}")
  end
end
