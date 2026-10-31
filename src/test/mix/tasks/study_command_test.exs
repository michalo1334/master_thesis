defmodule Mix.Study.CommandTest do
  @moduledoc """
  CMD-02: startup policy of the study commands.

  A driving command needs Gust workers that dispatch DAG runs. A read command
  inspects stored state, so another queued study must not dispatch work from that
  command VM.

  The cases replace the application start, so they inspect the role chosen for
  each mode without booting the application.
  """

  use ExUnit.Case, async: false

  alias Mix.Study.Command

  setup do
    previous_role = System.get_env("GUST_ROLE")
    on_exit(fn -> restore_role(previous_role) end)
    :ok
  end

  defp restore_role(nil), do: System.delete_env("GUST_ROLE")
  defp restore_role(role), do: System.put_env("GUST_ROLE", role)

  defp observing_start(parent) do
    fn application ->
      send(parent, {:started, application, System.get_env("GUST_ROLE")})
      {:ok, [application]}
    end
  end

  describe "execution mode" do
    test "rejects a Gust role without DAG dispatch before it starts the application" do
      for role <- ["console", "web"] do
        System.put_env("GUST_ROLE", role)
        parent = self()

        error =
          assert_raise Mix.Error, ~r/GUST_ROLE=#{role}/, fn ->
            Command.start!(:execute, observing_start(parent))
          end

        assert error.message =~ "GUST_ROLE=core"
        refute_received {:started, _application, _role}
      end
    end

    test "starts the application with the default execution role when GUST_ROLE is unset" do
      System.delete_env("GUST_ROLE")
      parent = self()

      assert :ok = Command.start!(:execute, observing_start(parent))
      assert_received {:started, :network_defense, "core"}
    end

    test "keeps a declared execution-capable role" do
      System.put_env("GUST_ROLE", "single")
      parent = self()

      assert :ok = Command.start!(:execute, observing_start(parent))
      assert_received {:started, :network_defense, "single"}
    end
  end

  describe "inspection mode" do
    test "starts the application with the non-executing console role" do
      System.put_env("GUST_ROLE", "single")
      parent = self()

      assert :ok = Command.start!(:inspect, observing_start(parent))
      assert_received {:started, :network_defense, "console"}
    end
  end

  test "a failed application start becomes a command error" do
    start = fn _application -> {:error, {:not_started, :network_defense}} end

    error =
      assert_raise Mix.Error, ~r/Cannot start the application/, fn ->
        Command.start!(:inspect, start)
      end

    assert error.message =~ "network_defense"
  end
end
