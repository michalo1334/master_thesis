defmodule NetworkDefense.MixProject do
  use Mix.Project

  def project do
    [
      app: :network_defense,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      releases: [
        network_defense: [
          applications: [opentelemetry_exporter: :permanent, opentelemetry: :temporary]
        ]
      ],
      aliases: aliases(),
      deps: deps(),
      dialyzer: [plt_add_apps: [:credo, :mix, :ex_unit]],
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {NetworkDefense.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:exograph, "== 0.9.12", only: [:dev, :test], runtime: true},
      {:ex_dna, "== 1.5.4", only: [:dev, :test], runtime: true},
      {:ex_ast, "== 0.12.9", only: [:dev, :test], runtime: true},
      {:agent_lib_elixir,
       [only: [:dev, :test], path: "../.agent-lib/elixir/installer", override: true]},
      {:live_debugger, "~> 1.0", only: [:dev]},
      {:live_svelte, "~> 0.18"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14.1", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.8.9"},
      {:phoenix_pubsub_redis, "~> 3.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:meck, "~> 1.2", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},
      {:logger_json, "~> 7.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3.0"},
      {:ex_json_schema, "0.11.5"},
      {:yaml_elixir, "~> 2.12"},
      {:gust, "0.1.40"},
      {:req, "~> 0.6.3"},
      {:bandit, "~> 1.5"},

      # OpenTelemetry
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_process_propagator, "~> 0.3"},
      {:opentelemetry_oban, "~> 1.0"},
      {:oban, "~> 2.19"},
      {:amqp, "~> 4.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.migrate",
        "ecto.migrate -r Gust.Repo --migrations-path deps/gust/priv/repo/migrations",
        "run priv/repo/seeds.exs"
      ],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "ecto.migrate --quiet -r Gust.Repo --migrations-path deps/gust/priv/repo/migrations",
        "test"
      ],
      "assets.setup": ["phoenix_vite.npm assets install"],
      "assets.build": [
        "phoenix_vite.npm vite build --manifest --emptyOutDir true",
        "phoenix_vite.npm vite build --ssrManifest --emptyOutDir false --ssr js/server.js --outDir ../priv/svelte"
      ],
      "assets.deploy": [
        "assets.build"
      ],
      precommit: [
        "compile --warning-as-errors",
        "gen.contracts",
        "format --check-formatted",
        "cmd npm run format:check",
        "cmd npm run typecheck",
        "assets.build",
        &__MODULE__.credo/1,
        "dialyzer",
        "sobelow --config --skip",
        "deps.unlock --unused",
        "test"
      ]
    ]
  end

  # Runs Credo in a separate OS process. An in-process run leaves a supervisor behind
  # that blocks later application startup through runtime tooling dependencies.
  #
  # Mix keeps the active environment and target in its own state instead of the OS
  # environment, so the child process receives both values explicitly. Every other
  # variable, for example MIX_TEST_PARTITION, is inherited from this process.
  def credo(_args) do
    {executable, args} = credo_command()
    run_isolated(executable, args)
  end

  def credo_command, do: {"mix", ["credo", "--strict"]}

  # Runs one child process, keeps its output visible and fails this process when the
  # child fails. The forwarding reads Mix state at execution time, not at alias build time.
  def run_isolated(executable, args) do
    {_, status} =
      System.cmd(executable, args,
        env: active_environment(),
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status == 0 do
      :ok
    else
      Mix.raise("#{executable} #{Enum.join(args, " ")} failed with exit status #{status}")
    end
  end

  defp active_environment do
    [{"MIX_ENV", to_string(Mix.env())}, {"MIX_TARGET", to_string(Mix.target())}]
  end
end
