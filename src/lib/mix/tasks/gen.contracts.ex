defmodule Mix.Tasks.Gen.Contracts do
  use Mix.Task
  @moduledoc false
  alias Mix.Tasks.Gen.Contracts.Registry

  @shortdoc "Generate TypeScript types from contract modules"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")
    Registry.generate_all()
    IO.puts("Generated contracts.generated.ts")
  end
end
