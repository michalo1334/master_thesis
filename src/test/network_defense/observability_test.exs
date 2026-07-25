defmodule NetworkDefense.ObservabilityTest do
  use ExUnit.Case, async: false

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias NetworkDefense.Observability
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

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

  test "formats GenServer termination reports as complete structured JSON" do
    Process.flag(:trap_exit, true)

    {:ok, pid} = NetworkDefense.TerminatingGenServer.start_link()
    GenServer.cast(pid, :crash)

    entry =
      fn event ->
        match?(%{msg: {:report, %{label: {:gen_server, :terminate}}}}, event)
      end
      |> receive_log_event()
      |> format_event()

    assert entry["message"] == "OTP report"
    assert entry["metadata"]["event"] == "otp.report"
    assert %{"crash_reason" => crash_reason, "report" => report} = entry["metadata"]["otp_report"]

    assert is_list(crash_reason)
    assert hd(crash_reason)["__struct__"] == "Elixir.RuntimeError"
    assert report["label"] == ["gen_server", "terminate"]
    assert report["last_message"] == ["$gen_cast", "crash"]
    assert report["state"] == "ready"
  end

  test "normalizes arbitrary OTP report values without discarding the report" do
    reference = make_ref()

    entry =
      %{
        level: :error,
        msg:
          {:report,
           %{
             label: {:external, :failure},
             report: %{opaque: {self(), reference, fn -> :ok end}}
           }},
        meta: %{domain: [:otp, :external], time: System.os_time(:microsecond)}
      }
      |> format_event()

    assert entry["message"] == "OTP report"
    assert entry["metadata"]["event"] == "otp.report"
    assert entry["metadata"]["otp_report"]["report"]["label"] == ["external", "failure"]

    assert [pid, normalized_reference, function] =
             entry["metadata"]["otp_report"]["report"]["report"]["opaque"]

    assert String.starts_with?(pid, "#PID<")
    assert String.starts_with?(normalized_reference, "#Reference<")
    assert String.starts_with?(function, "#Function<")
  end

  test "preserves external string logs and normalizes their metadata" do
    reference = make_ref()

    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    Logger.warning("external library message", opaque: {:value, self(), reference})

    entry =
      fn event -> Map.has_key?(event.meta, :opaque) end
      |> receive_log_event()
      |> format_event()

    assert entry["message"] == "external library message"

    assert ["value", pid, normalized_reference] = entry["metadata"]["opaque"]
    assert String.starts_with?(pid, "#PID<")
    assert String.starts_with?(normalized_reference, "#Reference<")
  end

  test "propagates trace context to task worker logs" do
    Tracer.with_span "observability.task_context" do
      {:ok, _pid} =
        TaskSupervisor.start_child(NetworkDefense.TaskSupervisor, fn ->
          Logger.info("task worker log")
        end)

      event =
        fn event -> event.msg == {:string, "task worker log"} end
        |> receive_log_event()

      assert is_binary(event.meta.otel_trace_id)
      assert is_binary(event.meta.otel_span_id)
    end
  end

  test "exports simulator metrics in Prometheus-supported types" do
    :telemetry.execute(
      [:network_defense, :simulator, :run],
      %{duration: System.convert_time_unit(250, :millisecond, :native)},
      %{}
    )

    scrape = TelemetryMetricsPrometheus.Core.scrape()

    assert scrape =~ "# TYPE network_defense_simulator_runs_total counter"
    assert scrape =~ "# TYPE network_defense_simulator_duration_seconds histogram"
  end

  test "emits Ecto telemetry as normalized structured metadata" do
    Observability.handle_telemetry_event(
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
      fn event -> Map.has_key?(event.meta, :telemetry) end
      |> receive_log_event()
      |> format_event()

    assert entry["message"] == "Telemetry event"
    assert entry["metadata"]["event"] == "telemetry.event"
    assert entry["metadata"]["telemetry"]["event"] == "network_defense.repo.query"
    assert entry["metadata"]["telemetry"]["measurements"]["query_time"] == 1_000

    assert entry["metadata"]["telemetry"]["metadata"]["params"] == [
             "node-1",
             %{"encoding" => "base64", "value" => "AP8="}
           ]

    assert entry["metadata"]["telemetry"]["metadata"]["stacktrace"]
  end

  test "emits LiveView telemetry as normalized structured metadata" do
    Observability.handle_telemetry_event(
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
      fn event -> Map.has_key?(event.meta, :telemetry) end
      |> receive_log_event()
      |> format_event()

    assert entry["metadata"]["telemetry"]["event"] == "phoenix.live_view.handle_event.start"
    assert entry["metadata"]["telemetry"]["metadata"]["event"] == "run_simulation_request"

    assert entry["metadata"]["telemetry"]["metadata"]["params"] == %{
             "request" => %{"run_count" => 1000}
           }
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
