# Run only through agent-lib configure after explicit approval.
if Code.ensure_loaded?(Igniter) do
  defmodule AgentLib.CredoSetup do
    def configure(igniter) do
      igniter =
        if File.exists?(".credo.exs"),
          do: igniter,
          else:
            Igniter.create_new_file(igniter, ".credo.exs", "%{configs: [%{name: \"default\"}]}\n")

      Igniter.update_elixir_file(igniter, ".credo.exs", fn zipper ->
        {node, count} =
          Macro.prewalk(Sourceror.Zipper.node(zipper), 0, fn
            {:%{}, metadata, pairs} = node, count ->
              original = fetch(pairs, :configs, nil)
              configs = literal(original)

              literal_configs? =
                is_list(configs) and
                  Enum.all?(configs, fn
                    {:%{}, _, entries} ->
                      Enum.any?(entries, fn {key, _} -> literal(key) == :name end)

                    _ ->
                      false
                  end)

              if literal_configs? do
                {configs, count} =
                  Enum.map_reduce(configs, count, fn {:%{}, meta, entries}, count ->
                    {{:%{}, meta, update_config(entries)}, count + 1}
                  end)

                configs =
                  case original do
                    {:__block__, meta, [_]} -> {:__block__, meta, [configs]}
                    _ -> configs
                  end

                {{:%{}, metadata, put(pairs, :configs, configs)}, count}
              else
                {node, count}
              end

            node, count ->
              {node, count}
          end)

        if count == 0 do
          Mix.raise(
            "Unsupported Credo configuration. Add ExDNA.Credo and ExSlop explicitly; no Credo file was replaced."
          )
        else
          {:ok, Sourceror.Zipper.replace(zipper, node)}
        end
      end)
    end

    defp literal({:__block__, _, [value]}), do: value
    defp literal(value), do: value

    defp fetch(pairs, key, default) do
      case Enum.find(pairs, fn {existing, _} -> literal(existing) == key end) do
        nil -> default
        {_, value} -> value
      end
    end

    defp put(pairs, key, value) do
      if Enum.any?(pairs, fn {existing, _} -> literal(existing) == key end) do
        Enum.map(pairs, fn {existing, old} ->
          {existing, if(literal(existing) == key, do: value, else: old)}
        end)
      else
        pairs ++ [{{:__block__, [format: :keyword], [key]}, value}]
      end
    end

    defp mentions?(node, module) do
      {_node, found} =
        Macro.prewalk(node, false, fn
          {:__aliases__, _, parts} = node, found -> {node, found or parts == module}
          node, found -> {node, found}
        end)

      found
    end

    defp append_unique(existing, additions) do
      # Parse the generated fragment with the same literal encoding as the source.
      # Keep the original node (and its comments) instead of round-tripping it through text.
      template =
        Sourceror.parse_string!(
          "Enum.uniq_by(__agent_lib_existing__() ++ (" <> additions <> "), &elem(&1, 0))"
        )

      Macro.prewalk(template, fn
        {:__agent_lib_existing__, _, []} -> existing
        node -> node
      end)
    end

    defp update_config(pairs) do
      plugins = fetch(pairs, :plugins, Sourceror.parse_string!("[]"))

      missing =
        [{[:ExDNA, :Credo], "{ExDNA.Credo, []}"}, {[:ExSlop], "{ExSlop, []}"}]
        |> Enum.reject(fn {module, _} -> mentions?(plugins, module) end)
        |> Enum.map(&elem(&1, 1))

      plugins =
        if missing == [] do
          plugins
        else
          append_unique(plugins, "[" <> Enum.join(missing, ", ") <> "]")
        end

      pairs = put(pairs, :plugins, plugins)

      # Credo treats an explicit enabled list as authoritative. Preserve that list,
      # but append the recommended checks instead of silently registering unused plugins.
      case fetch(pairs, :checks, nil) do
        {:%{}, metadata, checks} ->
          case fetch(checks, :enabled, nil) do
            nil ->
              pairs

            enabled ->
              if Macro.to_string(enabled) =~ "ExSlop.recommended_checks()" do
                pairs
              else
                enabled =
                  append_unique(
                    enabled,
                    "[{ExDNA.Credo, []}] ++ Enum.map(ExSlop.recommended_checks(), &{&1, []})"
                  )

                put(pairs, :checks, {:%{}, metadata, put(checks, :enabled, enabled)})
              end
          end

        _ ->
          pairs
      end
    end
  end

  defmodule Mix.Tasks.AgentLibElixir.Install do
    use Igniter.Mix.Task

    def info(_argv, _composing_task), do: %Igniter.Mix.Task.Info{}

    def igniter(igniter) do
      helper_path = Mix.Project.deps_paths() |> Map.fetch!(:agent_lib_elixir)
      request_path = helper_path |> Path.dirname() |> Path.dirname() |> Path.join("state/setup-request.json")
      request = request_path |> File.read!() |> JSON.decode!()

      igniter =
        Enum.reduce(request["dependencies"], igniter, fn {name, specification}, igniter ->
          options = [runtime: specification["runtime"]]

          options =
            if specification["only"] do
              Keyword.put(
                options,
                :only,
                Enum.map(specification["only"], &String.to_existing_atom/1)
              )
            else
              options
            end

          dependency = {String.to_atom(name), "== " <> specification["version"], options}
          Igniter.Project.Deps.add_dep(igniter, dependency, on_exists: :skip)
        end)

      igniter =
        if request["credo_plugins"] == [] do
          igniter
        else
          AgentLib.CredoSetup.configure(igniter)
        end

      igniter =
        if "phoenix-replay" in request["recipes"] do
          igniter
          |> Igniter.Project.Config.configure_new(
            "config.exs",
            :phoenix_replay,
            [:sample_rate],
            0.0
          )
          |> Igniter.add_notice(
            "A zero PhoenixReplay recording default was requested. Review existing overrides, privacy, retention, and access before starting the application."
          )
        else
          igniter
        end

      igniter
    end
  end
else
  defmodule Mix.Tasks.AgentLibElixir.Install do
    use Mix.Task

    def run(_argv),
      do: Mix.raise("Run this installer through agent-lib configure with Igniter available.")
  end
end
