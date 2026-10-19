defmodule NetworkDefense.Evaluation.GustConsole do
  @moduledoc false

  # Shared Gust-only console bootstrap.
  #
  # It starts Gust with one database connection and does not start the Network
  # Defense supervision tree, web listeners, application repository, Oban, or
  # RabbitMQ workers.

  def start!(start_application \\ &Application.ensure_all_started/1) do
    System.put_env("GUST_ROLE", "console")

    repo_config =
      :gust
      |> Application.fetch_env!(Gust.Repo)
      |> Keyword.put(:pool_size, 1)

    Application.put_env(:gust, Gust.Repo, repo_config)
    {:ok, _applications} = start_application.(:gust)
    :ok
  end
end
