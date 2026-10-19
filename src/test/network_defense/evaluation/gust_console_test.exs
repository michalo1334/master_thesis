defmodule NetworkDefense.Evaluation.GustConsoleTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.GustConsole

  setup do
    previous_role = System.get_env("GUST_ROLE")
    previous_repo = Application.fetch_env(:gust, Gust.Repo)

    on_exit(fn ->
      if previous_role,
        do: System.put_env("GUST_ROLE", previous_role),
        else: System.delete_env("GUST_ROLE")

      case previous_repo do
        {:ok, config} -> Application.put_env(:gust, Gust.Repo, config)
        :error -> Application.delete_env(:gust, Gust.Repo)
      end
    end)

    :ok
  end

  test "the console starts Gust only, with one database connection" do
    :gust
    |> Application.fetch_env!(Gust.Repo)
    |> Keyword.put(:pool_size, 10)
    |> then(&Application.put_env(:gust, Gust.Repo, &1))

    parent = self()

    start = fn applications ->
      send(parent, {:started, applications})
      {:ok, []}
    end

    assert :ok = GustConsole.start!(start)
    assert_received {:started, :gust}

    assert System.get_env("GUST_ROLE") == "console"
    assert Application.fetch_env!(:gust, Gust.Repo)[:pool_size] == 1
  end
end
