# Seeds one deterministic study scenario into the running development database
# and writes the test-only analysis stub archives.
#
# This script is a test-only end-to-end fixture. It never runs in production
# and it never changes production behavior. Run it inside the local app
# container against the running development database:
#
#     docker exec network-defense-local-app-site-east-0 \
#       sh -c 'cd /app && mix run --no-start test/support/study_e2e_seed.exs'
#
# `--no-start` skips the already-running endpoint. The script starts the Repo
# itself.
#
# `STUDY_E2E_FIXTURE_DIR` sets the archive output directory. The script prints
# one JSON record with the seeded identifiers so a browser driver can find the
# saved specification and the completed tier runs.

unless Process.whereis(NetworkDefense.Repo) do
  {:ok, _started} = Application.ensure_all_started(:ecto_sql)
  {:ok, _repo} = NetworkDefense.Repo.start_link()
end

Code.require_file("test/support/evaluation_fixtures.ex")

alias NetworkDefense.EvaluationFixtures

fixture_dir = System.get_env("STUDY_E2E_FIXTURE_DIR", "/tmp/study-e2e-fixtures")
File.mkdir_p!(fixture_dir)

tiers = ["small", "medium", "large"]
scenario = EvaluationFixtures.seed_study_scenario(tiers)

archives = %{
  "pilot_eligible.zip" => EvaluationFixtures.pilot_eligible_archive(tiers),
  "pilot_insufficient.zip" => EvaluationFixtures.pilot_insufficient_archive(tiers),
  "pilot_non_informative.zip" => EvaluationFixtures.pilot_non_informative_archive(tiers),
  "final.zip" => EvaluationFixtures.final_archive(tiers)
}

Enum.each(archives, fn {name, bytes} ->
  File.write!(Path.join(fixture_dir, name), bytes)
end)

payload = %{
  "specification_id" => scenario.specification.id,
  "study_id" => scenario.specification.study_id,
  "specification_version" => scenario.specification.specification_version,
  "pilot_runs" => Enum.map(scenario.runs, & &1.id),
  "final_runs" => Enum.map(scenario.final_runs, & &1.id),
  "warmup_run" => scenario.warmup_run.id,
  "running_run" => scenario.running_run.id,
  "fixture_dir" => fixture_dir
}

IO.puts("STUDY_E2E_SEED_JSON:" <> Jason.encode!(payload, pretty: true))
