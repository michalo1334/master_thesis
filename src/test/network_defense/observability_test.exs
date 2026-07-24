defmodule NetworkDefense.ObservabilityTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Observability

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :debug)

    handler = :network_defense_log_event_handler

    :ok =
      :logger.add_handler(handler, NetworkDefense.LogEventHandler, %{config: %{test_pid: self()}})

    on_exit(fn ->
      :logger.remove_handler(handler)
      Logger.configure(level: previous_level)
    end)

    :ok
  end

  test "formats GenServer termination reports as structured JSON while retaining metadata" do
    Process.flag(:trap_exit, true)

    {:ok, pid} = NetworkDefense.TerminatingGenServer.start_link()
    GenServer.cast(pid, :crash)

    assert_receive {:EXIT, ^pid, _reason}

    entry =
      fn event ->
        match?(%{msg: {:report, %{label: {:gen_server, :terminate}}}}, event)
      end
      |> receive_log_event()
      |> format_event()

    assert %{
             "event" => "otp.gen_server.terminate",
             "last_message" => ["$gen_cast", "crash"],
             "state" => "ready",
             "error" => %{
               "kind" => "error",
               "stacktrace" => stacktrace,
               "type" => "Elixir.RuntimeError"
             }
           } = entry["message"]

    assert is_binary(stacktrace)
    assert entry["metadata"]["otp_report"]["event"] == "otp.gen_server.terminate"
  end

  test "emits an Ecto query as a structured message and metadata" do
    Observability.handle_ecto_query(
      [:network_defense, :repo, :query],
      %{query_time: 1_000, queue_time: 2_000, decode_time: 3_000, total_time: 6_000},
      %{
        repo: NetworkDefense.Repo,
        query: "SELECT * FROM nodes WHERE id = $1",
        params: ["node-1", <<0, 255>>],
        source: "nodes",
        result: {:ok, %{num_rows: 1}},
        stacktrace: [
          {NetworkDefense.Repo, :all, 2, [file: ~c"lib/network_defense/repo.ex", line: 1]}
        ]
      },
      nil
    )

    entry =
      fn event -> Map.has_key?(event.meta, :ecto) end
      |> receive_log_event()
      |> format_event()

    assert %{
             "event" => "ecto.query",
             "query" => "SELECT * FROM nodes WHERE id = $1",
             "parameters" => ["node-1", %{"encoding" => "base64", "value" => "AP8="}],
             "source" => "nodes",
             "result" => "ok",
             "timings_us" => %{"query_time_us" => 1}
           } = entry["message"]

    assert entry["metadata"]["ecto"]["parameters"] == [
             "node-1",
             %{"encoding" => "base64", "value" => "AP8="}
           ]

    refute Map.has_key?(entry["message"], "stacktrace")
    refute Map.has_key?(entry["metadata"]["ecto"], "stacktrace")
  end

  test "emits a LiveView event as a structured message and metadata" do
    Observability.handle_live_view_handle_event(
      [:phoenix, :live_view, :handle_event, :start],
      %{},
      %{
        socket: %{view: NetworkDefenseWeb.DashboardLive},
        event: "run_simulation_request",
        params: %{"request" => %{"run_count" => 1000}}
      },
      nil
    )

    entry =
      fn event -> Map.has_key?(event.meta, :live_view) end
      |> receive_log_event()
      |> format_event()

    assert %{
             "event" => "live_view.handle_event",
             "view" => "NetworkDefenseWeb.DashboardLive",
             "name" => "run_simulation_request",
             "parameters" => %{"request" => %{"run_count" => 1000}}
           } = entry["message"]

    assert entry["metadata"]["live_view"]["event"] == "live_view.handle_event"
    assert entry["metadata"]["live_view"]["name"] == "run_simulation_request"
  end

  defp receive_log_event(predicate) do
    receive do
      {:log_event, event} ->
        if predicate.(event), do: event, else: receive_log_event(predicate)
    after
      1_000 ->
        flunk("did not receive the expected Logger event")
    end
  end

  defp format_event(event) do
    event
    |> NetworkDefense.Observability.LoggerFormatter.format(metadata: :all)
    |> IO.iodata_to_binary()
    |> Jason.decode!()
  end
end
