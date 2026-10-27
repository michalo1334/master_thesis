# This check evaluates the selected project's Mix configuration only after approval.
request = System.argv() |> hd() |> File.read!() |> JSON.decode!()
deps = Mix.Project.config()[:deps] || []
requested = Map.put(request["dependencies"], "igniter", %{"version" => "0.8.4"})

Enum.each(requested, fn {name, options} ->
  case Enum.find(deps, &(Atom.to_string(elem(&1, 0)) == name)) do
    nil ->
      :ok

    dependency ->
      requirement = elem(dependency, 1)

      unless is_binary(requirement) and Version.match?(options["version"], requirement) do
        Mix.raise(
          "Existing dependency #{name} conflicts with the selected recipe. No dependency was replaced."
        )
      end
  end
end)

if "phoenix-replay" in request["recipes"] and
     not Enum.any?(deps, &(elem(&1, 0) == :phoenix_live_view)) do
  Mix.raise("PhoenixReplay requires a Phoenix LiveView project.")
end

IO.puts("IGNITER_PRESENT=#{Enum.any?(deps, &(elem(&1, 0) == :igniter))}")
