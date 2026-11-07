# Run only against a fresh database owned by this UI verification session.
# Keep this VM alive through measured work. Stop it before removing that database.
if Mix.env() != :test, do: raise("Use MIX_ENV=test for the isolated Study UI journey")

expected = System.fetch_env!("STUDY_UI_OWNED_DATABASE")
partition = System.fetch_env!("MIX_TEST_PARTITION")

unless String.starts_with?(partition, "_study_ui_browser_") and
         expected == "network_defense_test#{partition}" do
  raise "The browser journey requires its owned disposable partition"
end

for {app, repo} <- [{:network_defense, NetworkDefense.Repo}, {:gust, Gust.Repo}] do
  config = Application.fetch_env!(app, repo)

  unless config[:database] == expected and config[:hostname] == "localhost",
    do: raise("Unexpected Repo target")

  Application.put_env(app, repo, Keyword.put(config, :pool, DBConnection.ConnectionPool))
end

label = "local-study-ui-#{partition}-single-vm-local-executor"
Application.put_env(:network_defense, :measured_environment_revision, label)

Application.put_env(:network_defense, NetworkDefense.Compute.ScatterGather,
  executor: NetworkDefense.Compute.LocalExecutor
)

endpoint = Application.fetch_env!(:network_defense, NetworkDefenseWeb.Endpoint)

endpoint =
  Keyword.merge(endpoint,
    server: true,
    http: [ip: {127, 0, 0, 1}, port: 4031],
    url: [host: "localhost", port: 4031],
    static_url: [host: "localhost", port: 4031]
  )

Application.put_env(:network_defense, NetworkDefenseWeb.Endpoint, endpoint)
{:ok, _apps} = Application.ensure_all_started(:network_defense)

{:ok, _loader} =
  Supervisor.start_child(
    NetworkDefense.Supervisor,
    {Gust.DAG.Loader.Worker, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}}
  )

Gust.DAG.Loader.Worker.get_definitions()

{:ok, _dispatcher} =
  Supervisor.start_child(NetworkDefense.Supervisor, {Gust.Run.DispatcherSupervisor, []})

attrs =
  NetworkDefense.Evaluation2Test.UiFixtures.attrs(
    System.get_env("STUDY_UI_STUDY_ID", "browser-journey")
  )

attrs =
  attrs
  |> put_in(["pilot", "candidates"], [%{"id" => "local-check", "plans" => 2, "attacks" => 32}])
  |> put_in(["simulation", "iterations_per_run"], 24)
  |> put_in(["pilot", "precision", "target_half_width"], 0.00001)

{:ok, parsed} = NetworkDefense.Evaluation2.Study.Definition.parse(attrs)

authored =
  parsed
  |> NetworkDefense.Evaluation2.Study.AuthoredDefinition.new()
  |> NetworkDefenseWeb.StudyWire.wire()

evidence_dir = System.get_env("STUDY_UI_EVIDENCE_DIR", "/tmp/study-ui-evidence")
File.mkdir_p!(evidence_dir)
File.write!(Path.join(evidence_dir, "browser-input.json"), Jason.encode!(authored, pretty: true))

IO.puts(
  Jason.encode!(%{
    ready: true,
    database: expected,
    role: System.get_env("GUST_ROLE", "single"),
    executor: "LocalExecutor",
    measurement_label: label,
    url: "http://localhost:4031"
  })
)

Process.sleep(:infinity)
