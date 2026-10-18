defmodule NetworkDefense.Evaluation.ComparisonConsoleTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Comparison.Console

  setup do
    original_role = System.get_env("GUST_ROLE")
    original_repo = Application.fetch_env!(:gust, Gust.Repo)

    on_exit(fn ->
      if original_role do
        System.put_env("GUST_ROLE", original_role)
      else
        System.delete_env("GUST_ROLE")
      end

      Application.put_env(:gust, Gust.Repo, original_repo)
    end)

    :ok
  end

  test "bootstrap configures a one-connection Gust console before starting only Gust" do
    System.put_env("GUST_ROLE", "single")
    original_repo = Application.fetch_env!(:gust, Gust.Repo)
    Application.put_env(:gust, Gust.Repo, Keyword.put(original_repo, :pool_size, 10))
    original_app_config = Application.get_all_env(:network_defense)
    parent = self()

    assert :ok =
             Console.start!(fn application ->
               send(parent, {:started, application})
               assert System.get_env("GUST_ROLE") == "console"

               assert Application.fetch_env!(:gust, Gust.Repo) ==
                        Keyword.put(original_repo, :pool_size, 1)

               {:ok, [application]}
             end)

    assert_receive {:started, :gust}
    refute_receive {:started, _application}
    assert Application.get_all_env(:network_defense) == original_app_config
  end

  test "isolated console startup does not start the web application or its services" do
    script = """
    :ok = NetworkDefense.Evaluation.Comparison.Console.start!()
    applications = Enum.map(Application.started_applications(), &elem(&1, 0))
    true = :gust in applications

    for application <- [:network_defense, :phoenix, :bandit, :oban, :amqp, :rabbit_common] do
      false = application in applications
    end

    for process <- [NetworkDefense.Supervisor, NetworkDefense.Repo,
                    NetworkDefenseWeb.Endpoint, NetworkDefense.Compute.RabbitMQ.Connection] do
      nil = Process.whereis(process)
    end

    "console" = System.get_env("GUST_ROLE")
    1 = Keyword.fetch!(Gust.Repo.config(), :pool_size)
    IO.puts("isolated console ready")
    """

    {output, status} =
      System.cmd("mix", ["run", "--no-start", "--no-compile", "-e", script],
        env: [{"MIX_ENV", "test"}, {"GUST_ROLE", "single"}, {"ERL_FLAGS", "+S 4:4"}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "isolated console ready"
  end

  test "named fixtures resolve through application priv at runtime" do
    for {name, relative_path} <- [
          {"crossed-small", "valid/crossed-small.request.json"},
          {"attack-column-count-mismatch", "invalid/attack-column-count-mismatch.request.json"}
        ] do
      path = Console.fixture_path!(name)

      assert path ==
               Application.app_dir(
                 :network_defense,
                 "priv/evaluation/contracts/v1/#{relative_path}"
               )

      assert File.regular?(path)
      assert %{"schema_version" => 1} = path |> File.read!() |> Jason.decode!()
    end
  end

  test "unknown fixture names are rejected" do
    assert_raise Mix.Error, "Unknown fixture \"unknown\".", fn ->
      Console.fixture_path!("unknown")
    end
  end
end
