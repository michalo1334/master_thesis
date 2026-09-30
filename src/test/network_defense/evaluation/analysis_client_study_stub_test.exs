if System.find_executable("python3") do
  defmodule NetworkDefense.Evaluation.AnalysisClientStudyStubTest do
    @moduledoc """
    Drives the real `AnalysisClient` HTTP request/response against the
    deterministic Python study stub.

    This test spawns the stub as an external process and points `AnalysisClient`
    at its address, so the client's real Req request, headers, status handling,
    content-type check, and body limit run against a real HTTP server. The stub
    stays a test-only double in `evaluation/analysis/tests`; no production code
    gains a test hook.

    The module is compiled only when `python3` is available. When it is absent,
    the focused `analysis_client_test.exs` still covers the client contract.
    """

    use ExUnit.Case, async: false

    alias NetworkDefense.Evaluation.AnalysisClient

    @stub_relative "evaluation/analysis/tests/study_stub_server.py"

    setup do
      stub = Path.expand("../#{@stub_relative}", File.cwd!())
      assert File.regular?(stub), "study stub server not found at #{stub}"

      directory =
        Path.join(System.tmp_dir!(), "study-stub-#{System.unique_integer([:positive])}")

      File.mkdir_p!(directory)
      on_exit(fn -> File.rm_rf(directory) end)

      File.write!(Path.join(directory, "pilot_eligible.zip"), "pilot-eligible-zip-bytes")
      File.write!(Path.join(directory, "pilot_insufficient.zip"), "pilot-insufficient-bytes")
      File.write!(Path.join(directory, "final.zip"), "final-analysis-zip-bytes")
      write_control(directory, %{"pilot" => "eligible", "analyze" => "final"})

      port = free_port()

      {pid, 0} =
        System.cmd("sh", [
          "-c",
          "python3 #{stub} --archives #{directory} " <>
            "--control #{Path.join(directory, "control.json")} " <>
            "--port #{port} >/dev/null 2>&1 & echo $!"
        ])

      pid = String.trim(pid)
      on_exit(fn -> System.cmd("kill", ["-TERM", pid], stderr_to_stdout: true) end)

      wait_for_stub(port)

      previous = Application.get_env(:network_defense, :analysis_service)

      Application.put_env(:network_defense, :analysis_service,
        url: "http://127.0.0.1:#{port}",
        connect_timeout_ms: 1_000,
        timeout_ms: 5_000,
        max_zip_bytes: 1_000_000
      )

      on_exit(fn -> Application.put_env(:network_defense, :analysis_service, previous) end)

      %{directory: directory}
    end

    test "round-trips the exact pilot ZIP bytes from the study pilot route", %{
      directory: directory
    } do
      expected = File.read!(Path.join(directory, "pilot_eligible.zip"))

      assert {:ok, archive} = AnalysisClient.analyze_study("study-bundle", "study-one", :pilot)
      assert archive == expected
    end

    test "round-trips the final ZIP bytes from the study analyze route", %{
      directory: directory
    } do
      write_control(directory, %{"pilot" => "eligible", "analyze" => "final"})
      expected = File.read!(Path.join(directory, "final.zip"))

      assert {:ok, archive} = AnalysisClient.analyze_study("study-bundle", "study-one", :analyze)
      assert archive == expected
    end

    test "maps a stub service failure to a stable transport error", %{directory: directory} do
      write_control(directory, %{"pilot" => "error", "analyze" => "error"})

      assert {:error, :http_status} =
               AnalysisClient.analyze_study("study-bundle", "study-one", :pilot)
    end

    defp write_control(directory, scenario) do
      File.write!(Path.join(directory, "control.json"), Jason.encode!(scenario))
    end

    defp free_port do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
      {:ok, port} = :inet.port(socket)
      :gen_tcp.close(socket)
      port
    end

    defp wait_for_stub(port, attempts \\ 100)

    defp wait_for_stub(_port, 0), do: flunk("study stub server did not start")

    defp wait_for_stub(port, attempts) do
      case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 100) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          :ok

        {:error, _reason} ->
          Process.sleep(50)
          wait_for_stub(port, attempts - 1)
      end
    end
  end
end
