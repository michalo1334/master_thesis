defmodule NetworkDefense.Evaluation.AnalysisClientTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.AnalysisClient

  setup do
    previous = Application.get_env(:network_defense, :analysis_service)

    Application.put_env(:network_defense, :analysis_service,
      url: "http://analysis.test",
      connect_timeout_ms: 100,
      timeout_ms: 1_000,
      max_zip_bytes: 32,
      plug: {Req.Test, __MODULE__}
    )

    on_exit(fn -> Application.put_env(:network_defense, :analysis_service, previous) end)
  end

  test "posts the raw archive and accepts both modes" do
    for mode <- ["pilot", "analyze"] do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/#{mode}"
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/zip"]
        assert Plug.Conn.get_req_header(conn, "accept") == ["application/zip"]
        assert Plug.Conn.get_req_header(conn, "x-correlation-id") == ["run-123"]
        assert Req.Test.raw_body(conn) == "phase-one-zip"

        conn
        |> Plug.Conn.put_resp_content_type("application/zip")
        |> Plug.Conn.send_resp(200, "result-zip")
      end)

      assert {:ok, "result-zip"} = AnalysisClient.analyze("phase-one-zip", "run-123", mode)
    end
  end

  test "rejects service and response contract failures" do
    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))
    assert {:error, :transport} = AnalysisClient.analyze("zip", "run", "analyze")

    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 503, "unavailable"))
    assert {:error, :http_status} = AnalysisClient.analyze("zip", "run", "analyze")

    Req.Test.expect(__MODULE__, &Plug.Conn.send_resp(&1, 200, "not a zip response"))
    assert {:error, :content_type} = AnalysisClient.analyze("zip", "run", "analyze")

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/zip; charset=binary")
      |> Plug.Conn.send_resp(200, String.duplicate("x", 33))
    end)

    assert {:error, :response_too_large} = AnalysisClient.analyze("zip", "run", "pilot")
    assert {:error, :invalid_mode} = AnalysisClient.analyze("zip", "run", "other")
  end

  test "emits one duration event for successful and failed calls" do
    event = [:network_defense, :evaluation, :analysis]
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      event,
      fn ^event, measurements, metadata, pid ->
        send(pid, {:analysis_telemetry, measurements, metadata})
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    Req.Test.expect(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/zip")
      |> Plug.Conn.send_resp(200, "result-zip")
    end)

    assert {:ok, "result-zip"} = AnalysisClient.analyze("input", "run-success", "pilot")

    assert_receive {:analysis_telemetry, %{duration: duration},
                    %{run_id: "run-success", mode: "pilot", status: "completed", error: nil}}

    assert is_integer(duration)
    refute_receive {:analysis_telemetry, _, _}

    Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))
    assert {:error, :transport} = AnalysisClient.analyze("input", "run-failure", "analyze")

    assert_receive {:analysis_telemetry, %{duration: duration},
                    %{run_id: "run-failure", mode: "analyze", status: "failed", error: :transport}}

    assert is_integer(duration)
    refute_receive {:analysis_telemetry, _, _}
  end
end
